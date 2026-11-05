import Foundation

// Read-only parser for the documented absolute-time TTML response. No external entities.
final class TTMLLyrics: NSObject, XMLParserDelegate {
    private struct Span { let depth: Int; let start: Double; let end: Double; let offset: Int; var hasTimedChild: Bool }
    private var lines: [LyricLine] = []
    private var text = ""
    private var segments: [LyricSegment] = []
    private var spans: [Span] = []
    private var depth = 0, bodyDepth = 0, lineDepth = 0, ignoredDepth = 0
    private var start = 0.0, end = 0.0
    static func time(_ raw: String?) -> Double? {
        guard var raw else { return nil }
        if raw.hasSuffix("s") { raw.removeLast() }
        let parts = raw.split(separator: ":", omittingEmptySubsequences: false)
        guard (1...3).contains(parts.count) else { return nil }
        var value = 0.0
        for (index, part) in parts.enumerated() {
            guard let n = Double(part), n.isFinite, n >= 0, (index == 0 || n < 60) else { return nil }
            value = value * 60 + n
        }
        return value <= 604800 ? value : nil
    }
    static func decode(_ data: Data) -> LyricsDocument? {
        struct Response: Decodable { let ttml: String; let score: Double? }
        guard data.count <= 524288, let response = try? JSONDecoder().decode(Response.self, from: data), response.score.map({ $0.isFinite && $0 >= 0.8 && $0 <= 1 }) ?? true else { return nil }
        return parse(response.ttml)
    }
    static func parse(_ xml: String) -> LyricsDocument? {
        guard xml.utf8.count <= 450000, !xml.uppercased().contains("<!DOCTYPE"), !xml.uppercased().contains("<!ENTITY"), let data = xml.data(using: .utf8) else { return nil }
        let delegate = TTMLLyrics(), parser = XMLParser(data: data)
        parser.shouldProcessNamespaces = true; parser.shouldResolveExternalEntities = false; parser.delegate = delegate
        guard parser.parse(), !delegate.lines.isEmpty else { return nil }
        let lines = delegate.lines.enumerated().sorted { $0.element.time == $1.element.time ? $0.offset < $1.offset : $0.element.time < $1.element.time }.map(\.element)
        return LyricsDocument(lines: lines, phase: lines.contains { !$0.segments.isEmpty } ? "word-synced" : "synced", source: "Better Lyrics")
    }
    func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName qName: String?, attributes attrs: [String: String]) {
        depth += 1
        guard depth <= 64 else { parser.abortParsing(); return }
        if name == "body" { bodyDepth = depth }
        guard bodyDepth > 0 else { return }
        if name == "p" {
            guard lineDepth == 0, let begin = Self.time(attrs["begin"]), let finish = Self.time(attrs["end"]), finish > begin else { return }
            lineDepth = depth; start = begin; end = finish; text = ""; segments = []; spans = []
        }
        guard lineDepth > 0, ignoredDepth == 0 else { return }
        if attrs.contains(where: { $0.key.hasSuffix("role") && ["x-bg", "x-translation", "x-roman"].contains($0.value) }) { ignoredDepth = depth; return }
        if name == "span", let begin = Self.time(attrs["begin"]), let finish = Self.time(attrs["end"]), finish > begin {
            for i in spans.indices { spans[i].hasTimedChild = true }
            spans.append(Span(depth: depth, start: max(start, begin), end: min(end, finish), offset: (text as NSString).length, hasTimedChild: false))
        }
    }
    func parser(_ parser: XMLParser, foundCharacters string: String) {
        guard lineDepth > 0, ignoredDepth == 0 else { return }
        guard (text as NSString).length + (string as NSString).length <= 4096 else { parser.abortParsing(); return }
        text += string
    }
    func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName qName: String?) {
        defer { depth -= 1 }
        if depth == ignoredDepth { ignoredDepth = 0; return }
        guard ignoredDepth == 0 else { return }
        if name == "span", let span = spans.last, span.depth == depth {
            spans.removeLast()
            let length = (text as NSString).length - span.offset
            if !span.hasTimedChild && length > 0 && span.end > span.start {
                guard segments.count < 1024 else { parser.abortParsing(); return }
                segments.append(LyricSegment(start: span.start, end: span.end, range: NSRange(location: span.offset, length: length)))
            }
        }
        if name == "p", lineDepth == depth {
            guard lines.count < 2000 else { parser.abortParsing(); return }
            lines.append(LyricLine(time: start, text: text, end: end, segments: segments.sorted { $0.start < $1.start }))
            lineDepth = 0; spans = []
        }
        if name == "body" { bodyDepth = 0 }
    }
}
