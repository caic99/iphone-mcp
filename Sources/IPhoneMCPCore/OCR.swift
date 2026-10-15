import CoreGraphics
import Vision

public struct TextLine: Codable, Equatable, Sendable {
    public var text: String
    public var x, y, w, h: Int
    public var confidence: Double
    public init(text: String, x: Int, y: Int, w: Int, h: Int, confidence: Double) {
        self.text = text; self.x = x; self.y = y; self.w = w; self.h = h; self.confidence = confidence
    }
    public var centerX: Int { x + w / 2 }
    public var centerY: Int { y + h / 2 }
}

public enum OCR {
    /// Recognise text in `image`; boxes are returned in image pixels divided by `outputScale`
    /// (pass 2 for a 2× capture to get 1× model coordinates).
    public static func recognize(_ image: CGImage, outputScale: Double) throws -> [TextLine] {
        let req = VNRecognizeTextRequest()
        req.recognitionLevel = .accurate
        req.usesLanguageCorrection = false
        req.recognitionLanguages = ["zh-Hans", "zh-Hant", "en-US"]
        try VNImageRequestHandler(cgImage: image).perform([req])
        let W = Double(image.width), H = Double(image.height)
        let lines: [TextLine] = (req.results ?? []).compactMap { obs in
            guard let c = obs.topCandidates(1).first else { return nil }
            let bb = obs.boundingBox   // normalised, origin bottom-left
            return TextLine(text: c.string,
                            x: Int((bb.minX * W / outputScale).rounded()),
                            y: Int(((1 - bb.maxY) * H / outputScale).rounded()),
                            w: Int((bb.width * W / outputScale).rounded()),
                            h: Int((bb.height * H / outputScale).rounded()),
                            confidence: (Double(c.confidence) * 100).rounded() / 100)
        }
        return readingOrder(lines)
    }

    /// One element per line, "text @x,y,w,h" — about a third of the JSON's size and cheaper than an image.
    public static func compact(_ lines: [TextLine]) -> String {
        lines.isEmpty ? "(no text recognised)" : lines.map { "\($0.text) @\($0.x),\($0.y),\($0.w),\($0.h)" }.joined(separator: "\n")
    }

    /// Top-to-bottom rows (lines whose vertical centres are within half a line height), each left-to-right.
    public static func readingOrder(_ lines: [TextLine]) -> [TextLine] {
        let byY = lines.sorted { ($0.centerY, $0.x) < ($1.centerY, $1.x) }
        var rows: [[TextLine]] = []
        for l in byY {
            if let first = rows.last?.first, abs(l.centerY - first.centerY) <= max(first.h / 2, 1) {
                rows[rows.count - 1].append(l)
            } else {
                rows.append([l])
            }
        }
        return rows.flatMap { $0.sorted { $0.x < $1.x } }
    }
}
