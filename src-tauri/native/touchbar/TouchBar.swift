import AppKit
import WebKit
import CoreText

@_silgen_name("ytm_state") private func rustState(_ json: UnsafePointer<CChar>)
@_silgen_name("ytm_command") private func rustCommand(_ json: UnsafePointer<CChar>)

private struct Player: Decodable {
    var title: String?, artist: String?, album: String?, artworkUrl: String?
    var playbackRate: Double
    var duration: Double?, currentTime: Double?
    var isAd: Bool
    var isPlaying: Bool, canSeek: Bool, canNext: Bool, canPrevious: Bool
}

// Bounded, cookie-free artwork requests; redirects must pass the same URL policy.
private final class Artwork: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    private var bytes = Data()
    private var completion: ((Data?) -> Void)?
    private var session: URLSession?
    static func allowed(_ url: URL) -> Bool {
        guard url.scheme == "https", url.port == nil || url.port == 443, url.user == nil, url.password == nil, let host = url.host else { return false }
        return ["ytimg.com", "googleusercontent.com", "ggpht.com"].contains { host == $0 || host.hasSuffix("." + $0) }
    }
    func load(_ url: URL, completion: @escaping (Data?) -> Void) {
        self.completion = completion
        let config = URLSessionConfiguration.ephemeral
        config.httpCookieStorage = nil; config.httpShouldSetCookies = false
        config.timeoutIntervalForRequest = 10; config.timeoutIntervalForResource = 15
        let session = URLSession(configuration: config, delegate: self, delegateQueue: nil)
        self.session = session; session.dataTask(with: url).resume()
    }
    func cancel() { session?.invalidateAndCancel(); session = nil }
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(request.url.flatMap { Self.allowed($0) ? request : nil })
    }
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse, completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        let valid = (response as? HTTPURLResponse)?.statusCode == 200 && response.mimeType?.hasPrefix("image/") == true && response.expectedContentLength <= 2_000_000
        completionHandler(valid ? .allow : .cancel)
    }
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        guard bytes.count + data.count <= 2_000_000 else { dataTask.cancel(); return }
        bytes.append(data)
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        completion?(error == nil ? bytes : nil); completion = nil
        session.finishTasksAndInvalidate()
    }
}


@MainActor private final class KaraokeView: NSView {
    private var text = "Choose a song"
    private var sweep: LyricSweep?
    private var base = CTLineCreateWithAttributedString(NSAttributedString(string: "Choose a song", attributes: [.font: NSFont.systemFont(ofSize: 13, weight: .medium), .foregroundColor: NSColor.labelColor]))
    private var filled = CTLineCreateWithAttributedString(NSAttributedString(string: "Choose a song", attributes: [.font: NSFont.systemFont(ofSize: 13, weight: .medium), .foregroundColor: NSColor.systemRed]))
    override init(frame: NSRect) { super.init(frame: frame); setAccessibilityElement(true); setAccessibilityRole(.staticText); setAccessibilityLabel("Current lyric") }
    convenience init() { self.init(frame: .zero) }
    required init?(coder: NSCoder) { super.init(coder: coder) }
    func update(text: String, sweep: LyricSweep?) {
        // Keep glyph metrics fixed while the color mask moves: no per-syllable font changes.
        if self.text != text || (self.sweep == nil) != (sweep == nil) {
            self.text = text
            let font = NSFont.systemFont(ofSize: 13, weight: .medium)
            base = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: sweep == nil ? NSColor.labelColor : NSColor.secondaryLabelColor]))
            filled = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: NSColor.systemRed]))
            setAccessibilityValue(text)
        }
        self.sweep = sweep; needsDisplay = true
    }
    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        let length = (text as NSString).length
        var ascent: CGFloat = 0, descent: CGFloat = 0
        let width = CGFloat(CTLineGetTypographicBounds(base, &ascent, &descent, nil))
        let start = CTLineGetOffsetForStringIndex(base, 0, nil)
        let end = CTLineGetOffsetForStringIndex(base, length, nil)
        var cursor = start
        if let sweep, sweep.range.location >= 0, NSMaxRange(sweep.range) <= length {
            let from = CTLineGetOffsetForStringIndex(base, sweep.range.location, nil)
            let to = CTLineGetOffsetForStringIndex(base, NSMaxRange(sweep.range), nil)
            cursor = from + (to - from) * sweep.fraction
        }
        // Follow the moving fill edge, rather than jumping the scroll position per word.
        let offset = sweep == nil ? 0 : min(max(0, cursor - bounds.width * 0.55), max(0, width - bounds.width))
        let origin = CGPoint(x: -offset, y: (bounds.height - ascent - descent) / 2 + descent)
        context.saveGState(); context.clip(to: bounds); context.textMatrix = .identity
        context.textPosition = origin; CTLineDraw(base, context)
        if sweep != nil {
            let left = end >= start ? 0 : cursor
            let right = end >= start ? cursor : width
            context.clip(to: CGRect(x: left - offset, y: 0, width: max(0, right - left), height: bounds.height))
            context.textPosition = origin; CTLineDraw(filled, context)
        }
        context.restoreGState()
    }
}

// Keep the seek thumb within its own row on the 30-point Touch Bar.
@MainActor private final class CompactSeekCell: NSSliderCell {
    override var knobThickness: CGFloat { 8 }
    override func knobRect(flipped: Bool) -> NSRect {
        let native = super.knobRect(flipped: flipped)
        return NSRect(x: native.midX - 4, y: native.midY - 4, width: 8, height: 8)
    }
    override func drawKnob(_ knobRect: NSRect) {
        (isEnabled ? NSColor.labelColor : NSColor.disabledControlTextColor).setFill()
        NSBezierPath(ovalIn: knobRect).fill()
    }
}

@MainActor private final class Controller: NSResponder, NSTouchBarDelegate {
    weak var web: WKWebView?
    let world = WKContentWorld.world(name: "YTMTouchBar")
    let play = NSButton(), previous = NSButton(), next = NSButton()
    let titleLabel = NSTextField(labelWithString: "YouTube Music")
    let artistLabel = NSTextField(labelWithString: "Choose a track")
    let timeLabel = NSTextField(labelWithString: "—:—")
    let slider = NSSlider(value: 0, minValue: 0, maxValue: 1, target: nil, action: nil)
    let image = NSImageView()
    let lyricLabel = KaraokeView()
    let nextLyricLabel = NSTextField(labelWithString: "LRCLIB · Synced lyrics")
    let lyrics = LyricsService()
    let adBlocker = AdBlocker()
    var globalTouchBar: GlobalTouchBar?
    var statusItem: NSStatusItem?
    var globalMenuItems: [NSMenuItem] = []
    var lyricsEnabled = UserDefaults.standard.object(forKey: "lyricsEnabled") as? Bool ?? true
    var lyricsPhase = "idle"

    var navigation: Navigation?
    var loadError: String?
    var handler: Handler?
    var artwork: Artwork?
    var artworkURL: String?
    var state: Player?
    var generation = 0
    var observations: [NSKeyValueObservation] = []
    var status: NSTextField?
    var windowObserver: NSObjectProtocol?
    var appObservers: [NSObjectProtocol] = []
    let placeholder = NSImage(systemSymbolName: "music.note", accessibilityDescription: "Album artwork")

    override func makeTouchBar() -> NSTouchBar? {
        globalTouchBar?.enabled == true ? nil : buildTouchBar()
    }
    func buildTouchBar() -> NSTouchBar {
        let bar = NSTouchBar(); bar.delegate = self
        let identifiers = lyricsEnabled ? ["previous", "play", "next", "lyrics", "lyrics-toggle"] : ["artwork", "track", "previous", "play", "next", "progress", "lyrics-toggle"]
        bar.defaultItemIdentifiers = identifiers.map { NSTouchBarItem.Identifier($0) }
        return bar
    }
    func touchBar(_ touchBar: NSTouchBar, makeItemForIdentifier identifier: NSTouchBarItem.Identifier) -> NSTouchBarItem? {
        let item = NSCustomTouchBarItem(identifier: identifier)
        switch identifier.rawValue {
        case "artwork": image.image = placeholder; image.imageScaling = .scaleProportionallyUpOrDown; image.widthAnchor.constraint(equalToConstant: 30).isActive = true; item.view = image
        case "track":
            titleLabel.font = .systemFont(ofSize: 12, weight: .medium)
            artistLabel.font = .systemFont(ofSize: 10); artistLabel.textColor = .secondaryLabelColor
            [titleLabel, artistLabel].forEach {
                $0.lineBreakMode = .byTruncatingTail
                $0.setContentHuggingPriority(NSLayoutConstraint.Priority(1), for: .horizontal)
                $0.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            }
            let stack = NSStackView(views: [titleLabel, artistLabel]); stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 0
            // Let metadata absorb available width rather than reserving a blank spacer.
            stack.widthAnchor.constraint(greaterThanOrEqualToConstant: 150).isActive = true
            stack.setContentHuggingPriority(NSLayoutConstraint.Priority(1), for: .horizontal)
            item.view = stack
            item.visibilityPriority = .normal
        case "previous", "play", "next":
            let button = identifier.rawValue == "previous" ? previous : identifier.rawValue == "next" ? next : play
            button.image = NSImage(systemSymbolName: identifier.rawValue == "previous" ? "backward.end.fill" : identifier.rawValue == "next" ? "forward.end.fill" : (state?.isPlaying == true ? "pause.fill" : "play.fill"), accessibilityDescription: identifier.rawValue)
            button.target = self
            button.action = identifier.rawValue == "previous" ? #selector(goPrevious) : identifier.rawValue == "next" ? #selector(goNext) : #selector(toggle)
            button.isEnabled = identifier.rawValue == "previous" ? (state?.canPrevious ?? false) : identifier.rawValue == "next" ? (state?.canNext ?? false) : state?.currentTime != nil
            if button === play { button.bezelColor = .systemRed }
            item.view = button; item.visibilityPriority = .high
        case "lyrics":
            nextLyricLabel.font = .systemFont(ofSize: 10); nextLyricLabel.textColor = .secondaryLabelColor
            nextLyricLabel.lineBreakMode = .byTruncatingTail
            lyricLabel.widthAnchor.constraint(equalToConstant: 300).isActive = true
            lyricLabel.heightAnchor.constraint(equalToConstant: 16).isActive = true
            let stack = NSStackView(views: [lyricLabel, nextLyricLabel]); stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 0
            stack.widthAnchor.constraint(equalToConstant: 300).isActive = true; item.view = stack; item.visibilityPriority = .normal
        case "lyrics-toggle":
            let button = NSButton(image: NSImage(systemSymbolName: "text.bubble", accessibilityDescription: "Toggle lyrics")!, target: self, action: #selector(toggleLyrics))
            if lyricsEnabled { button.bezelColor = .systemRed }; item.view = button
        case "progress":
            slider.target = self; slider.action = #selector(seek); slider.isContinuous = false; slider.isEnabled = state?.canSeek ?? false
            if !(slider.cell is CompactSeekCell) {
                slider.cell = CompactSeekCell()
                slider.minValue = 0; slider.maxValue = max(1, state?.duration ?? 1)
                slider.doubleValue = state?.currentTime ?? 0
                slider.target = self; slider.action = #selector(seek)
                slider.isContinuous = false; slider.isEnabled = state?.canSeek ?? false
                slider.controlSize = .small
                slider.setAccessibilityLabel("Track position")
                NSLayoutConstraint.activate([
                    slider.widthAnchor.constraint(equalToConstant: 100),
                    slider.heightAnchor.constraint(equalToConstant: 14),
                    timeLabel.heightAnchor.constraint(equalToConstant: 11)
                ])
            }
            timeLabel.font = .monospacedDigitSystemFont(ofSize: 9, weight: .regular)
            timeLabel.alignment = .center
            timeLabel.setContentCompressionResistancePriority(.required, for: .vertical)
            let stack = NSStackView(views: [slider, timeLabel]); stack.orientation = .vertical
            stack.alignment = .centerX; stack.spacing = 3
            item.view = stack; item.visibilityPriority = .low
        default: return nil
        }
        return item
    }
    func command(_ value: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: value), let json = String(data: data, encoding: .utf8) else { return }
        json.withCString { rustCommand($0) }
    }
    @objc func toggleLyrics() {
        lyricsEnabled.toggle(); UserDefaults.standard.set(lyricsEnabled, forKey: "lyricsEnabled")
        if let globalTouchBar { globalTouchBar.refreshLayout() } else { web?.window?.touchBar = buildTouchBar() }
        if let state { updateLyrics(state) }
    }
    func refreshVisibility() {
        let suspended = globalTouchBar?.suspended ?? false
        lyrics.setVisible(!suspended && (NSApp.isActive || globalTouchBar?.rendersInBackground == true))
        globalMenuItems.forEach { $0.state = globalTouchBar?.enabled == true ? .on : .off; $0.isEnabled = globalTouchBar?.supported == true }
    }
    @objc func toggleGlobal() { globalTouchBar?.toggle(); refreshVisibility() }
    @objc func disableGlobal() { globalTouchBar?.setEnabled(false); refreshVisibility() }
    @objc func showMusic() { web?.window?.deminiaturize(nil); web?.window?.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true) }
    func installGlobalControls(_ window: NSWindow) {
        let driver = GlobalTouchBar(window: window) { [weak self] in self?.buildTouchBar() ?? NSTouchBar() }
        globalTouchBar = driver
        driver.onChange = { [weak self] in self?.refreshVisibility() }
        let menuItem = NSMenuItem(title: "Keep Touch Bar Visible (Experimental)", action: #selector(toggleGlobal), keyEquivalent: "")
        menuItem.target = self; NSApp.mainMenu?.items.first?.submenu?.insertItem(menuItem, at: 0); globalMenuItems.append(menuItem)
        let status = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        status.button?.title = "♫"; status.button?.toolTip = "Touchtrack"
        let menu = NSMenu()
        let show = NSMenuItem(title: "Show Touchtrack", action: #selector(showMusic), keyEquivalent: ""); show.target = self; menu.addItem(show)
        let global = NSMenuItem(title: "Keep Touch Bar Visible (Experimental)", action: #selector(toggleGlobal), keyEquivalent: ""); global.target = self; menu.addItem(global); globalMenuItems.append(global)
        let restore = NSMenuItem(title: "Restore Normal Touch Bar", action: #selector(disableGlobal), keyEquivalent: ""); restore.target = self; menu.addItem(restore)
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit Touchtrack", action: #selector(NSApplication.terminate(_:)), keyEquivalent: ""); quit.target = NSApp; menu.addItem(quit)
        status.menu = menu; statusItem = status
        refreshVisibility(); driver.restorePreference()
    }
    func updateLyrics(_ value: Player) {
        lyrics.update(title: value.title, artist: value.artist, duration: value.duration, position: value.currentTime, enabled: lyricsEnabled, isAd: value.isAd, album: value.album, isPlaying: value.isPlaying, playbackRate: value.playbackRate)
    }
    @objc func toggle() { command(["type": "toggle"]) }
    @objc func goPrevious() { command(["type": "previous"]) }
    @objc func goNext() { command(["type": "next"]) }
    @objc func seek() { command(["type": "seek", "time": slider.doubleValue]) }
    func dispatch(_ json: String) {
        guard let data = json.data(using: .utf8), let value = try? JSONSerialization.jsonObject(with: data) as? [String: Any], web?.url?.host == "music.youtube.com" else { return }
        web?.callAsyncJavaScript("if(location.origin==='https://music.youtube.com') await window.ytmCommand?.(command)", arguments: ["command": value], in: nil, in: world) { [weak self] result in
            if case .failure = result { self?.artistLabel.stringValue = "Player command unavailable" }
        }
    }
    func render(_ json: String) {
        guard let data = json.data(using: .utf8), let value = try? JSONDecoder().decode(Player.self, from: data) else { return }
        state = value
        updateLyrics(value)
        titleLabel.stringValue = value.title ?? "YouTube Music"
        artistLabel.stringValue = value.artist ?? "Choose a track"
        play.isEnabled = value.currentTime != nil
        previous.isEnabled = value.canPrevious; next.isEnabled = value.canNext
        play.image = NSImage(systemSymbolName: value.isPlaying ? "pause.fill" : "play.fill", accessibilityDescription: value.isPlaying ? "Pause" : "Play")
        slider.isEnabled = value.canSeek
        if slider.currentEditor() == nil && !(NSEvent.pressedMouseButtons != 0) {
            slider.maxValue = max(1, value.duration ?? 1); slider.doubleValue = value.currentTime ?? 0
        }
        func clock(_ seconds: Double?) -> String { guard let seconds else { return "—:—" }; let n = Int(seconds); return String(format: "%d:%02d", n / 60, n % 60) }
        timeLabel.stringValue = clock(value.currentTime) + " / " + clock(value.duration)
        if value.artworkUrl != artworkURL {
            artworkURL = value.artworkUrl; generation += 1; let current = generation
            artwork?.cancel(); artwork = nil; image.image = placeholder
            if let raw = artworkURL, let url = URL(string: raw), Artwork.allowed(url) {
                let loader = Artwork(); artwork = loader
                loader.load(url) { [weak self] data in
                    DispatchQueue.main.async { [weak self] in
                        guard let self, self.generation == current, let data, let icon = ArtworkImage.decode(data) else { return }
                        self.image.image = icon
                    }
                }
            }
        }
    }
    func reset() {
        "{\"title\":null,\"artist\":null,\"artworkUrl\":null,\"duration\":null,\"currentTime\":null,\"isPlaying\":false,\"canSeek\":false,\"canNext\":false,\"canPrevious\":false}".withCString { rustState($0) }
    }
    func attach(_ view: WKWebView, script: String) {
        web = view
        lyrics.onChange = { [weak self] current, next, phase in
            self?.nextLyricLabel.stringValue = next; self?.lyricsPhase = phase
        }
        lyrics.onHighlight = { [weak self] text, sweep in
            self?.lyricLabel.update(text: text, sweep: sweep)
        }
        lyrics.setVisible(NSApp.isActive)
        for notification in [NSApplication.didBecomeActiveNotification, NSApplication.didResignActiveNotification] {
            appObservers.append(NotificationCenter.default.addObserver(forName: notification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.refreshVisibility() }
            })
        }
        let navigation = Navigation(owner: self, original: view.navigationDelegate)
        self.navigation = navigation; view.navigationDelegate = navigation
        let handler = Handler(self); self.handler = handler
        view.configuration.userContentController.add(handler, contentWorld: world, name: "player")
        view.configuration.userContentController.addUserScript(WKUserScript(source: script, injectionTime: .atDocumentStart, forMainFrameOnly: true, in: world))
        if let window = view.window {
            nextResponder = window.nextResponder; window.nextResponder = self; window.touchBar = buildTouchBar()
            installGlobalControls(window)
            window.setFrameAutosaveName("YTMusicMainWindow")
            let note = NSTextField(labelWithString: "Loading YouTube Music…")
            note.backgroundColor = .windowBackgroundColor; note.drawsBackground = true; note.alignment = .center
            note.translatesAutoresizingMaskIntoConstraints = false; view.addSubview(note)
            NSLayoutConstraint.activate([note.leadingAnchor.constraint(equalTo: view.leadingAnchor), note.trailingAnchor.constraint(equalTo: view.trailingAnchor), note.topAnchor.constraint(equalTo: view.topAnchor), note.heightAnchor.constraint(equalToConstant: 24)])
            status = note
            windowObserver = NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: window, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.teardown() }
            }
        }
        observations.append(view.observe(\.isLoading, options: [.new]) { [weak self] view, _ in
            MainActor.assumeIsolated {
                if view.isLoading { self?.loadError = nil; self?.reset(); self?.status?.isHidden = false; self?.status?.stringValue = "Loading… · Reload with ⌘R" }
                else { self?.status?.isHidden = self?.loadError == nil; if let error = self?.loadError { self?.status?.stringValue = error } }
            }
        })
        // Music-origin compatibility token only. Rust blocks auth navigation here.
        view.evaluateJavaScript("navigator.userAgent") { [weak self] result, error in
            guard error == nil, let agent = result as? String else { self?.status?.stringValue = "Unable to initialize WebView. Relaunch to retry."; return }
            view.customUserAgent = agent + " Safari/605.1.15 YTMTouchBar/0.1 WKWebView"
            self?.adBlocker.attach(view) { [weak self, weak view] in
                guard let self, let view else { return }
                if self.adBlocker.status.contains("failed") { self.status?.stringValue = self.adBlocker.status }
                view.load(URLRequest(url: URL(string: "https://music.youtube.com")!))
            }
        }
    }
    func failed(_ error: String) {
        reset(); loadError = error + " · Retry with ⌘R"
        status?.stringValue = loadError ?? error; status?.isHidden = false
    }
    func teardown() {
        globalTouchBar?.stop(); globalTouchBar = nil
        if let statusItem { NSStatusBar.system.removeStatusItem(statusItem) }; statusItem = nil
        reset(); lyrics.stop(); adBlocker.stop(); artwork?.cancel(); artwork = nil; observations.removeAll()
        web?.configuration.userContentController.removeScriptMessageHandler(forName: "player", contentWorld: world)
        web?.navigationDelegate = navigation?.original; navigation = nil
        appObservers.forEach { NotificationCenter.default.removeObserver($0) }; appObservers = []
        if let observer = windowObserver { NotificationCenter.default.removeObserver(observer) }; windowObserver = nil
    }
}
// Preserve Tauri's navigation policy and callbacks through Objective-C forwarding.
@MainActor private final class Navigation: NSObject, WKNavigationDelegate {
    weak var owner: Controller?
    weak var original: (any WKNavigationDelegate)?
    init(owner: Controller, original: (any WKNavigationDelegate)?) { self.owner = owner; self.original = original }
    override func responds(to selector: Selector!) -> Bool { super.responds(to: selector) || original?.responds(to: selector) == true }
    override func forwardingTarget(for selector: Selector!) -> Any? { original }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        original?.webView?(webView, didFailProvisionalNavigation: navigation, withError: error)
        if (error as NSError).code != NSURLErrorCancelled { owner?.failed("Unable to load YouTube Music. Check your connection.") }
    }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        original?.webView?(webView, didFail: navigation, withError: error)
        if (error as NSError).code != NSURLErrorCancelled { owner?.failed("Page loading failed.") }
    }
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        original?.webViewWebContentProcessDidTerminate?(webView)
        owner?.failed("Web player stopped.")
    }
}
@MainActor private final class Handler: NSObject, WKScriptMessageHandler {
    weak var owner: Controller?
    init(_ owner: Controller) { self.owner = owner }
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard owner != nil, message.frameInfo.isMainFrame, message.frameInfo.securityOrigin.protocol == "https", message.frameInfo.securityOrigin.host == "music.youtube.com", message.frameInfo.securityOrigin.port == 443 || message.frameInfo.securityOrigin.port == 0,
              JSONSerialization.isValidJSONObject(message.body), let data = try? JSONSerialization.data(withJSONObject: message.body), data.count <= 16384, let json = String(data: data, encoding: .utf8) else { return }
        json.withCString { rustState($0) }
    }
}
@MainActor private var controller: Controller?
@_cdecl("ytm_attach") func attach(_ pointer: UnsafeMutableRawPointer, _ script: UnsafePointer<CChar>) {
    MainActor.assumeIsolated {
        let view = Unmanaged<WKWebView>.fromOpaque(pointer).takeUnretainedValue()
        let c = Controller(); controller = c; c.attach(view, script: String(cString: script))
    }
}
@_cdecl("ytm_render") func render(_ json: UnsafePointer<CChar>) { MainActor.assumeIsolated { controller?.render(String(cString: json)) } }
@_cdecl("ytm_dispatch") func dispatch(_ json: UnsafePointer<CChar>) { MainActor.assumeIsolated { controller?.dispatch(String(cString: json)) } }

@_cdecl("ytm_show_status") func showStatus() {
    MainActor.assumeIsolated {
        let alert = NSAlert(); alert.messageText = controller?.titleLabel.stringValue ?? "No player"
        if let c = controller { alert.informativeText = c.artistLabel.stringValue + "\n" + c.timeLabel.stringValue + "\n" + (c.state?.isPlaying == true ? "Playing" : "Paused") + "\nSeek: \(c.slider.isEnabled) · Previous: \(c.previous.isEnabled) · Next: \(c.next.isEnabled)" }
        alert.informativeText += "\nLyrics: \(controller?.lyricsPhase ?? "idle") · Cues: \(controller?.lyrics.lineCount ?? 0) · Active cue: \(controller?.lyrics.activeIndex.map(String.init) ?? "none")"
        alert.informativeText += "\nLyrics request: \(controller?.lyrics.diagnostic ?? "none")"
        alert.informativeText += "\nSource: \(controller?.lyrics.source ?? "none") · Active timed segment: \(controller?.lyrics.activeSegment.map { "\($0.location):\($0.length)" } ?? "none")"
        alert.informativeText += "\nAlbum: \(controller?.state?.album ?? "unknown") · Better Lyrics: \(controller?.lyrics.richDiagnostic ?? "none")"
        alert.informativeText += "\nAd blocker: \(controller?.adBlocker.status ?? "not initialized")"
        alert.informativeText += "\nGlobal Touch Bar: \(controller?.globalTouchBar?.status ?? "off") · Supported: \(controller?.globalTouchBar?.supported ?? false)"
        alert.runModal()
    }
}

@_cdecl("ytm_toggle_lyrics") func toggleLyricsMode() { MainActor.assumeIsolated { controller?.toggleLyrics() } }

@_cdecl("ytm_adblock_enabled") func adBlockEnabled() -> Bool { MainActor.assumeIsolated { UserDefaults.standard.object(forKey: "adBlockEnabled") as? Bool ?? true } }
@_cdecl("ytm_toggle_adblock") func toggleAdBlock() -> Bool { MainActor.assumeIsolated { controller?.adBlocker.toggle() ?? false } }

