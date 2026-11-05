import Foundation
import AppKit
import ImageIO

enum LyricsRetryDelay {
    // Untrusted server headers must never reach DispatchTime as huge/NaN values.
    static func seconds(_ header: String?, fallback: Double, now: Date = Date()) -> Double {
        let safeFallback = fallback.isFinite ? min(300, max(1, fallback)) : 60
        guard let header else { return safeFallback }
        let raw = header.trimmingCharacters(in: .whitespacesAndNewlines)
        if let seconds = Double(raw) {
            return seconds.isFinite ? min(300, max(1, seconds)) : safeFallback
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        guard let date = formatter.date(from: raw) else { return safeFallback }
        return min(300, max(1, date.timeIntervalSince(now)))
    }
}

enum ArtworkImage {
    static func dimensionsAllowed(width: Double, height: Double) -> Bool {
        width.isFinite && height.isFinite && width >= 1 && height >= 1
            && width <= 8192 && height <= 8192 && width * height <= 16_000_000
    }
    static func decode(_ data: Data) -> NSImage? {
        guard data.count <= 2_000_000,
              let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? NSNumber,
              let height = properties[kCGImagePropertyPixelHeight] as? NSNumber,
              dimensionsAllowed(width: width.doubleValue, height: height.doubleValue) else { return nil }
        // Decode only a small, static thumbnail for the Touch Bar, never all frames.
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: 128,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
    }
}
