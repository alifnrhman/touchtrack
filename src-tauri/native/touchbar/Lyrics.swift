import Foundation

struct LyricSegment: Equatable {
    let start: Double
    let end: Double
    let range: NSRange
}
struct LyricSweep: Equatable {
    let range: NSRange
    let fraction: Double
}
struct LyricLine: Equatable {
    let time: Double
    let text: String
    let end: Double?
    let segments: [LyricSegment]
    init(time: Double, text: String, end: Double? = nil, segments: [LyricSegment] = []) {
        self.time = time; self.text = text; self.end = end; self.segments = segments
    }
    func sweep(at time: Double) -> LyricSweep? {
        guard time.isFinite, let first = segments.first else { return nil }
        let segment = segments.last { time >= $0.start } ?? first
        let length = segment.end - segment.start
        guard length > 0 else { return nil }
        return LyricSweep(range: segment.range, fraction: min(1, max(0, (time - segment.start) / length)))
    }
    func highlight(at time: Double) -> NSRange? {
        segments.last { time >= $0.start && time < $0.end }?.range
    }
}
struct LyricsRecord: Decodable {
    let trackName: String?
    let artistName: String?
    let duration: Double?
    let instrumental: Bool?
    let syncedLyrics: String?
    let plainLyrics: String?
}
struct LyricsDocument {
    let lines: [LyricLine]
    let phase: String
    let source: String
    init(lines: [LyricLine], phase: String, source: String = "LRCLIB") {
        self.lines = lines; self.phase = phase; self.source = source
    }
    static func decode(_ data: Data) -> LyricsDocument? {
        guard data.count <= 524288, let record = try? JSONDecoder().decode(LyricsRecord.self, from: data) else { return nil }
        if record.instrumental == true { return LyricsDocument(lines: [], phase: "instrumental") }
        let lines = parse(record.syncedLyrics ?? "")
        return LyricsDocument(lines: lines, phase: !lines.isEmpty ? "synced" : record.plainLyrics?.isEmpty == false ? "unsynced" : "unavailable")
    }
    static func parse(_ input: String) -> [LyricLine] {
        guard input.utf8.count <= 262144 else { return [] }
        let rows = input.components(separatedBy: .newlines)
        let offsetPattern = try! NSRegularExpression(pattern: #"^\[offset:([+-]?\d+)\]$"#, options: [.caseInsensitive])
        var offset = 0.0
        for row in rows {
            let range = NSRange(row.startIndex..., in: row)
            if let match = offsetPattern.firstMatch(in: row, range: range), let r = Range(match.range(at: 1), in: row), let n = Double(row[r]), n.isFinite, abs(n) <= 60000 { offset = n / 1000 }
        }
        let timestamp = try! NSRegularExpression(pattern: #"\[(\d{1,3}):([0-5]\d(?:[.:]\d{1,3})?)\]"#)
        var result: [(LyricLine, Int)] = []
        for row in rows {
            let matches = timestamp.matches(in: row, range: NSRange(row.startIndex..., in: row))
            guard let first = matches.first, first.range.location == 0, let last = matches.last, let end = Range(last.range, in: row)?.upperBound else { continue }
            let text = String(row[end...].trimmingCharacters(in: .whitespaces).prefix(512))
            for match in matches {
                guard let m = Range(match.range(at: 1), in: row), let s = Range(match.range(at: 2), in: row), let minutes = Double(row[m]), let seconds = Double(row[s].replacingOccurrences(of: ":", with: ".")) else { continue }
                result.append((LyricLine(time: max(0, minutes * 60 + seconds - offset), text: text), result.count))
                if result.count >= 2000 { break }
            }
            if result.count >= 2000 { break }
        }
        return result.sorted { $0.0.time == $1.0.time ? $0.1 < $1.1 : $0.0.time < $1.0.time }.map { $0.0 }
    }
    func active(at time: Double) -> Int? {
        guard time.isFinite, let first = lines.first, time >= first.time else { return nil }
        var low = 0, high = lines.count
        while low < high { let mid = (low + high) / 2; if lines[mid].time <= time { low = mid + 1 } else { high = mid } }
        return low - 1
    }
}

private final class LyricsRequest: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    private var bytes = Data()
    private var response: HTTPURLResponse?
    private var completion: ((Data?, HTTPURLResponse?, String) -> Void)?
    private var session: URLSession?
    func start(_ url: URL, completion: @escaping (Data?, HTTPURLResponse?, String) -> Void) {
        self.completion = completion
        let config = URLSessionConfiguration.ephemeral
        config.httpCookieStorage = nil; config.httpShouldSetCookies = false
        config.timeoutIntervalForRequest = 12; config.timeoutIntervalForResource = 15
        let session = URLSession(configuration: config, delegate: self, delegateQueue: nil); self.session = session
        var request = URLRequest(url: url)
        request.setValue("YouTubeMusicTouchBar/0.1 (macOS; development build)", forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        session.dataTask(with: request).resume()
    }
    func cancel() { session?.invalidateAndCancel(); session = nil }
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        // The documented API is fixed; redirects are never needed.
        completionHandler(nil)
    }
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse, completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        self.response = response as? HTTPURLResponse
        completionHandler(response.expectedContentLength <= 524288 ? .allow : .cancel)
    }
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        guard bytes.count + data.count <= 524288 else { dataTask.cancel(); return }; bytes.append(data)
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        completion?(error == nil ? bytes : nil, response, error.map { "\(($0 as NSError).domain):\(($0 as NSError).code)" } ?? "HTTP \(response?.statusCode ?? 0)"); completion = nil; session.finishTasksAndInvalidate()
    }
}

@MainActor final class LyricsService {
    var onChange: ((String, String, String) -> Void)?
    var onHighlight: ((String, LyricSweep?) -> Void)?
    private(set) var activeSegment: NSRange?
    private(set) var source = "LRCLIB"
    private(set) var richDiagnostic = "Not requested"
    private var album = ""
    private var sampledAt = ProcessInfo.processInfo.systemUptime
    private var playing = false
    private var rate = 1.0
    private var ticker: Timer?
    private var visible = true
    private var lastHighlight = ""
    private var richRetryAfter = Date.distantPast
    private var currentPosition: Double { min(duration, position + (playing ? max(0, ProcessInfo.processInfo.systemUptime - sampledAt) * rate : 0)) }
    func setVisible(_ value: Bool) { visible = value; configureTicker() }
    private func configureTicker() {
        let needed = visible && playing && phase == "word-synced"
        if !needed { ticker?.invalidate(); ticker = nil }
        else if ticker == nil {
            let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in MainActor.assumeIsolated { self?.display() } }
            timer.tolerance = 0.003; ticker = timer; RunLoop.main.add(timer, forMode: .common)
        }
    }
    private(set) var diagnostic = "No request"
    private(set) var phase = "idle"
    private(set) var activeIndex: Int?
    private(set) var lineCount = 0
    private var key = ""
    private var duration = 0.0
    private var position = 0.0
    private var generation = 0
    private var document: LyricsDocument?
    private var request: LyricsRequest?
    private var pending: DispatchWorkItem?
    private var cache: [String: LyricsDocument] = [:]
    private var cacheOrder: [String] = []
    private var retryAfter = Date.distantPast
    private var lastRequest = Date.distantPast
    private var lastDisplay = ""

    func update(title: String?, artist: String?, duration: Double?, position: Double?, enabled: Bool, isAd: Bool, album: String? = nil, isPlaying: Bool = false, playbackRate: Double = 1) {
        self.position = position ?? 0
        sampledAt = ProcessInfo.processInfo.systemUptime; playing = isPlaying
        rate = playbackRate.isFinite && playbackRate > 0 && playbackRate <= 4 ? playbackRate : 1
        guard enabled else { clear("disabled"); return }
        guard !isAd else { clear("ad"); return }
        guard let title, !title.isEmpty, let artist, !artist.isEmpty, let duration, duration.isFinite, duration >= 1, duration <= 3600 else { clear("idle"); return }
        let identity = title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() + "\u{1f}" + artist.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() + "\u{1f}" + (album ?? "")
        if identity != key || abs(duration - self.duration) > 3 {
            generation += 1; let token = generation
            pending?.cancel(); request?.cancel(); request = nil
            self.album = album ?? ""
            key = identity; self.duration = duration; document = nil; lineCount = 0
            let cacheKey = identity + "\u{1f}" + String(Int(duration.rounded()))
            if let cached = cache[cacheKey] { document = cached; phase = cached.phase; source = cached.source; lineCount = cached.lines.count; display(); return }
            guard Date() >= retryAfter else { phase = "rate-limited"; display(); return }
            phase = "loading"; display()
            let work = DispatchWorkItem { [weak self] in
                guard let self, token == self.generation else { return }
                var url = URLComponents(string: "https://lrclib.net/api/get")!
                url.queryItems = [URLQueryItem(name: "track_name", value: String(title.prefix(256))), URLQueryItem(name: "artist_name", value: String(artist.prefix(256))), URLQueryItem(name: "duration", value: String(Int(duration.rounded())))]
                guard let target = url.url else { return }
                if let album, !album.isEmpty, Date() >= self.richRetryAfter {
                    var rich = URLComponents(string: "https://api.betterlyrics.org/getLyrics")!
                    rich.queryItems = [URLQueryItem(name: "s", value: String(title.prefix(256))), URLQueryItem(name: "a", value: String(artist.prefix(256))), URLQueryItem(name: "al", value: String(album.prefix(256))), URLQueryItem(name: "d", value: String(Int(duration.rounded())))]
                    if let url = rich.url { self.fetchRich(url, fallback: target, cacheKey: cacheKey, token: token); return }
                }
                self.fetch(target, cacheKey: cacheKey, token: token, attempt: 0)
            }
            pending = work
            DispatchQueue.main.asyncAfter(deadline: .now() + max(0.5, 0.35 - Date().timeIntervalSince(lastRequest)), execute: work)
        }
        display()
    }
    private func delay(_ response: HTTPURLResponse?, fallback: Double) -> Double {
        LyricsRetryDelay.seconds(response?.value(forHTTPHeaderField: "Retry-After"), fallback: fallback)
    }
    private func fetch(_ target: URL, cacheKey: String, token: Int, attempt: Int) {
                self.lastRequest = Date()
                let request = LyricsRequest(); self.request = request
                request.start(target) { [weak self] data, response, diagnostic in
                    DispatchQueue.main.async {
                        guard let self, token == self.generation else { return }
                        self.request = nil
                        self.diagnostic = diagnostic
                        if response?.statusCode == 429 {
                            self.retryAfter = Date().addingTimeInterval(max(60, self.delay(response, fallback: 60)) + Double.random(in: 1...5))
                            self.phase = "rate-limited"
                        } else if response?.statusCode == 503 {
                            if attempt < 2 {
                                let delay = max(self.delay(response, fallback: pow(2, Double(attempt))), 1) + Double.random(in: 0.2...0.5)
                                self.phase = "retrying"
                                let work = DispatchWorkItem { [weak self] in
                                    guard let self, self.generation == token else { return }
                                    self.fetch(target, cacheKey: cacheKey, token: token, attempt: attempt + 1)
                                }
                                self.pending = work
                                DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
                            } else { self.phase = "busy" }
                        } else if response?.statusCode == 404 {
                            self.phase = "unavailable"
                            self.remember(LyricsDocument(lines: [], phase: "unavailable"), key: cacheKey)
                        } else if response?.statusCode == 200, let data, let doc = LyricsDocument.decode(data) {
                            self.document = doc; self.phase = doc.phase; self.source = doc.source; self.lineCount = doc.lines.count
                            self.remember(doc, key: cacheKey)
                        } else { self.phase = "error" }
                        self.display()
                    }
                }
    }
    private func fetchRich(_ target: URL, fallback: URL, cacheKey: String, token: Int) {
        lastRequest = Date(); let request = LyricsRequest(); self.request = request
        request.start(target) { [weak self] data, response, diagnostic in
            DispatchQueue.main.async {
                guard let self, self.generation == token else { return }
                self.request = nil; self.richDiagnostic = diagnostic; self.diagnostic = "Better Lyrics: " + diagnostic
                if response?.statusCode == 200, let data, let doc = TTMLLyrics.decode(data), doc.phase == "word-synced" {
                    self.document = doc; self.phase = doc.phase; self.source = doc.source; self.lineCount = doc.lines.count
                    self.remember(doc, key: cacheKey); self.display()
                } else {
                    // A 401 cache miss is a normal, supported fallback. No token/key bypass.
                    if response?.statusCode == 429 || response?.statusCode == 503 {
                        self.richRetryAfter = Date().addingTimeInterval(max(60, self.delay(response, fallback: 60)))
                    }
                    let work = DispatchWorkItem { [weak self] in
                        guard let self, self.generation == token else { return }
                        self.fetch(fallback, cacheKey: cacheKey, token: token, attempt: 0)
                    }
                    self.pending = work; DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: work)
                }
            }
        }
    }
    private func remember(_ doc: LyricsDocument, key: String) {
        cache[key] = doc; cacheOrder.removeAll { $0 == key }; cacheOrder.append(key)
        if cacheOrder.count > 40 { cache.removeValue(forKey: cacheOrder.removeFirst()) }
    }
    private func clear(_ phase: String) {
        if !key.isEmpty || self.phase != phase {
            generation += 1; pending?.cancel(); request?.cancel(); request = nil
            playing = false; ticker?.invalidate(); ticker = nil
            key = ""; document = nil; activeIndex = nil; lineCount = 0; self.phase = phase
        }
        display()
    }
    private func display() {
        configureTicker()
        let playbackTime = currentPosition
        var current = "", next = source + " · Synced lyrics"
        activeSegment = nil
        var sweep: LyricSweep?
        activeIndex = nil
        switch phase {
        case "synced", "word-synced":
            if let doc = document {
                activeIndex = doc.active(at: playbackTime)
                if let index = activeIndex {
                    sweep = doc.lines[index].sweep(at: playbackTime)
                    if doc.lines[index].end.map({ playbackTime < $0 }) ?? true { activeSegment = doc.lines[index].highlight(at: playbackTime) }
                    current = doc.lines[index].text.isEmpty ? "♪" : doc.lines[index].text
                    if index + 1 < doc.lines.count { next = doc.lines[index + 1].text }
                } else { current = "♪"; next = doc.lines.first?.text ?? "" }
            }
        case "loading": current = "Finding lyrics…"
        case "instrumental": current = "Instrumental ♪"
        case "unsynced": current = "Only unsynced lyrics available"
        case "unavailable": current = "No synced lyrics for this song"
        case "retrying": current = "Lyrics service busy…"; next = "Retrying shortly"
        case "busy": current = "Lyrics service busy"; next = "Toggle lyrics off/on to retry later"
        case "rate-limited": current = "Lyrics service busy"; next = "Try another track later"
        case "error": current = "Lyrics request failed"; next = "Reload music to retry"
        case "ad": current = "Advertisement"; next = "Lyrics resume with the song"
        case "disabled": current = "Lyrics off"
        default: current = "Choose a song"; next = "LRCLIB · Synced lyrics"
        }
        let display = phase + "\u{1f}" + current + "\u{1f}" + next
        if display != lastDisplay { lastDisplay = display; onChange?(current, next, phase) }
        let highlight = current + "\u{1f}" + (sweep.map { "\($0.range.location):\($0.range.length):\(Int(($0.fraction * 1000).rounded()))" } ?? "none")
        if highlight != lastHighlight { lastHighlight = highlight; onHighlight?(current, sweep) }
    }
    func stop() { clear("disabled"); onChange = nil; onHighlight = nil }
}
