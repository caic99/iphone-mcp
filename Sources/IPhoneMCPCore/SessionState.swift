import Foundation

/// A live stream exposes no AX elements inside the window; the lock / "iPhone in Use" /
/// connect screens are native Mac views and do (finding from phone-harness, holds on any locale).
public enum SessionState: Equatable, Sendable {
    case ready
    case blocked([String])

    /// Fails closed: if the window's AX tree could not be read we cannot tell a live stream from a lock screen.
    public static func from(nodes: [(role: String, text: String)], rootReadable: Bool) -> SessionState {
        guard rootReadable else { return .blocked(["cannot verify the phone stream"]) }
        guard !nodes.isEmpty else { return .ready }
        return .blocked(nodes.map { $0.text.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty })
    }
}
