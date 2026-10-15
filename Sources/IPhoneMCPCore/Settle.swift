import CoreGraphics

public enum Settle {
    public static let maxChangedFraction = 0.005
    public static func isSettled(_ a: CGImage, _ b: CGImage) -> Bool {
        ImageOps.changedFraction(a, b) < maxChangedFraction
    }
}
