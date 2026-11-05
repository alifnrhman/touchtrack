import AppKit

@_silgen_name("ytm_global_supported") private func privateSupported() -> Bool
@_silgen_name("ytm_global_present") private func privatePresent(_ bar: UnsafeMutableRawPointer) -> Bool
@_silgen_name("ytm_global_dismiss") private func privateDismiss(_ bar: UnsafeMutableRawPointer) -> Bool

@MainActor final class GlobalTouchBar {
    private weak var window: NSWindow?
    private let makeBar: () -> NSTouchBar
    var onChange: (() -> Void)?
    private var bar: NSTouchBar?
    private var pending: DispatchWorkItem?
    private var workspaceObservers: [NSObjectProtocol] = []
    private var appObservers: [NSObjectProtocol] = []
    private var generation = 0
    private(set) var enabled = false
    private(set) var suspended = false
    private(set) var presentationRequested = false
    private(set) var status = "Off"
    var supported: Bool { privateSupported() }
    var rendersInBackground: Bool { enabled && presentationRequested && !suspended }
    static var savedEnabled: Bool { UserDefaults.standard.bool(forKey: "globalTouchBarExperimental") }

    init(window: NSWindow, makeBar: @escaping () -> NSTouchBar) {
        self.window = window; self.makeBar = makeBar
        let workspace = NSWorkspace.shared.notificationCenter
        for notification in [NSWorkspace.didActivateApplicationNotification, NSWorkspace.didWakeNotification, NSWorkspace.sessionDidBecomeActiveNotification] {
            workspaceObservers.append(workspace.addObserver(forName: notification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.resumeSoon(sessionActive: notification == NSWorkspace.sessionDidBecomeActiveNotification) }
            })
        }
        workspaceObservers.append(workspace.addObserver(forName: NSWorkspace.sessionDidResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }; self.suspended = true
                self.generation += 1; self.pending?.cancel(); self.dismiss()
                self.status = self.enabled ? "Suspended for inactive session" : "Off"; self.onChange?()
            }
        })
        for notification in [NSWindow.didMiniaturizeNotification, NSWindow.didDeminiaturizeNotification] {
            appObservers.append(NotificationCenter.default.addObserver(forName: notification, object: window, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.schedulePresentation() }
            })
        }
        appObservers.append(NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.stop() }
        })
    }
    func restorePreference() { if Self.savedEnabled { setEnabled(true) } }
    @discardableResult func toggle() -> Bool { setEnabled(!enabled); return enabled }
    func setEnabled(_ value: Bool, persist: Bool = true) {
        generation += 1; pending?.cancel()
        dismiss(); bar = nil
        enabled = value && supported
        if persist { UserDefaults.standard.set(enabled, forKey: "globalTouchBarExperimental") }
        if enabled {
            // Only one bar owns the existing views at a time.
            window?.touchBar = nil; bar = makeBar(); present()
        } else {
            window?.touchBar = makeBar()
            status = value ? "Unavailable on this macOS — normal mode restored" : "Off"
        }
        onChange?()
    }
    func refreshLayout() {
        generation += 1; pending?.cancel(); dismiss()
        if enabled { window?.touchBar = nil; bar = makeBar(); present() }
        else { bar = nil; window?.touchBar = makeBar() }
        onChange?()
    }
    private func resumeSoon(sessionActive: Bool) {
        // No activation or focus stealing: only request presentation from our own process.
        if sessionActive { suspended = false }; schedulePresentation()
    }
    private func schedulePresentation() {
        guard enabled, !suspended else { return }
        generation += 1; let token = generation; pending?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.enabled, !self.suspended, self.generation == token else { return }
            self.dismiss(); self.present(); self.onChange?()
        }
        pending = work; DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: work)
    }
    private func present() {
        guard enabled, !suspended, let bar else { return }
        presentationRequested = privatePresent(Unmanaged.passUnretained(bar).toOpaque())
        if presentationRequested { status = "Global requested — experimental" }
        else {
            enabled = false; UserDefaults.standard.set(false, forKey: "globalTouchBarExperimental")
            self.bar = nil; window?.touchBar = makeBar(); status = "Presentation failed — normal mode restored"
        }
    }
    private func dismiss() {
        if presentationRequested, let bar {
            if !privateDismiss(Unmanaged.passUnretained(bar).toOpaque()) { status = "Dismiss failed — quit app to release global bar" }
        }
        presentationRequested = false
    }
    func stop() {
        generation += 1; pending?.cancel(); dismiss(); enabled = false; bar = nil
        let workspace = NSWorkspace.shared.notificationCenter
        workspaceObservers.forEach { workspace.removeObserver($0) }; workspaceObservers = []
        appObservers.forEach { NotificationCenter.default.removeObserver($0) }; appObservers = []
        onChange?(); onChange = nil
    }
}
