import CoreGraphics

public struct Insets: Equatable, Sendable {
    public var top, left, bottom, right: Double
    public init(top: Double, left: Double, bottom: Double, right: Double) {
        self.top = top; self.left = left; self.bottom = bottom; self.right = right
    }
}

/// Maps the model's coordinate space (1× screenshot pixels, origin at the phone
/// screen's top-left) to global screen points (CGWindow space, origin top-left).
public struct PhoneGeometry: Equatable, Sendable {
    /// Window chrome around the phone screen, in points (measured on macOS 27).
    public static let bezel = Insets(top: 38, left: 8, bottom: 8, right: 8)

    public let windowFrame: CGRect
    public let inset: Insets

    public init(windowFrame: CGRect, inset: Insets = PhoneGeometry.bezel) {
        self.windowFrame = windowFrame
        self.inset = inset
    }

    public var screenRectInWindow: CGRect {
        CGRect(x: inset.left, y: inset.top,
               width: windowFrame.width - inset.left - inset.right,
               height: windowFrame.height - inset.top - inset.bottom)
    }

    public var screenSize: CGSize { screenRectInWindow.size }

    /// Is a global point over the phone screen (not the title-bar toolbar or bezel)?
    public func screenContains(global p: CGPoint) -> Bool {
        screenRectInWindow.offsetBy(dx: windowFrame.minX, dy: windowFrame.minY).contains(p)
    }

    public func toGlobal(x: Double, y: Double) throws -> CGPoint {
        let s = screenSize
        guard x.isFinite, y.isFinite, x >= 0, y >= 0, x < s.width, y < s.height else {
            throw MirrorError.outOfBounds(x: x, y: y, width: s.width, height: s.height)
        }
        return CGPoint(x: windowFrame.minX + inset.left + x, y: windowFrame.minY + inset.top + y)
    }
}
