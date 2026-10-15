import Foundation

public enum TextMatcher {
    /// Exact (trimmed) match first, else case-insensitive substring. Multiple matches need `occurrence` (1-based).
    public static func find(_ query: String, in lines: [TextLine], occurrence: Int?) throws -> TextLine {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { throw MirrorError.invalidArgument("text must not be empty") }
        var matches = lines.filter { $0.text.trimmingCharacters(in: .whitespacesAndNewlines) == q }
        if matches.isEmpty {
            matches = lines.filter { $0.text.range(of: q, options: [.caseInsensitive]) != nil }
        }
        guard !matches.isEmpty else { throw MirrorError.textNotFound(q) }
        if let n = occurrence {
            guard n >= 1, n <= matches.count else {
                throw MirrorError.invalidArgument("occurrence \(n) out of range 1...\(matches.count)")
            }
            return matches[n - 1]
        }
        guard matches.count == 1 else {
            throw MirrorError.textAmbiguous(query: q, matches: matches.map { "\($0.text) @ (\($0.centerX),\($0.centerY))" })
        }
        return matches[0]
    }
}
