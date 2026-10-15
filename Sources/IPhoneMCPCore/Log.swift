import Foundation

/// Optional action log: tool name and argument KEYS only — never values (type_text may be private), never images.
enum Log {
    static let path = ProcessInfo.processInfo.environment["IPHONE_MCP_LOG"]

    static func action(_ name: String, keys: [String], outcome: String) {
        guard let path else { return }
        let line = "\(ISO8601DateFormatter().string(from: Date())) \(name) [\(keys.sorted().joined(separator: ","))] \(outcome)\n"
        if let h = FileHandle(forWritingAtPath: path) {
            h.seekToEndOfFile(); h.write(line.data(using: .utf8)!); try? h.close()
        } else {
            try? line.write(toFile: path, atomically: true, encoding: .utf8)
        }
    }
}
