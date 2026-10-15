import CoreGraphics

public struct WindowCandidate: Equatable, Sendable {
    public let id: CGWindowID
    public let title: String
    public let bounds: CGRect
    public init(id: CGWindowID, title: String, bounds: CGRect) { self.id = id; self.title = title; self.bounds = bounds }
}

public enum WindowPicker {
    /// The phone window is titled like the app. While Mirroring is still connecting only side windows
    /// exist (e.g. "Welcome to iPhone Mirroring"); never pick one with a different title.
    public static func pick(_ candidates: [WindowCandidate], appName: String) -> WindowCandidate? {
        let big = candidates.filter { $0.bounds.height > 300 && $0.bounds.width > 200 }
        if let titled = big.first(where: { $0.title == appName }) { return titled }
        return big.filter { $0.title.isEmpty }.max { $0.bounds.width * $0.bounds.height < $1.bounds.width * $1.bounds.height }
    }
}
