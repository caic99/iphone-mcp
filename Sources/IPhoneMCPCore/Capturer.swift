import CoreGraphics
import ScreenCaptureKit

public struct Screenshot {
    public let full: CGImage       // phone screen at capture resolution (2×)
    public let model: CGImage      // 1× — the model's coordinate space
    public let geometry: PhoneGeometry
    public let frameID: Int
    public var pixelsPerPoint: Double { Double(full.width) / Double(model.width) }
}

public actor Capturer {
    private var counter = 0
    public init() {}

    public func capture(_ t: MirrorTarget) async throws -> Screenshot {
        let content: SCShareableContent
        do {
            content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
        } catch {
            throw MirrorError.permissionScreen(app: Permissions.responsibleAppName())
        }
        guard let w = content.windows.first(where: { $0.windowID == t.windowID }) else {
            throw MirrorError.phoneNotConnected(detail: "phone window is not capturable")
        }
        let cfg = SCStreamConfiguration()
        cfg.width = Int(t.frame.width * 2)
        cfg.height = Int(t.frame.height * 2)
        cfg.showsCursor = false
        let img = try await SCScreenshotManager.captureImage(
            contentFilter: SCContentFilter(desktopIndependentWindow: w), configuration: cfg)
        let g = t.geometry
        let s = Double(img.width) / Double(t.frame.width)
        guard let full = ImageOps.crop(img, windowPointRect: g.screenRectInWindow, pixelsPerPoint: s),
              let model = ImageOps.resize(full, width: Int(g.screenSize.width.rounded()),
                                          height: Int(g.screenSize.height.rounded())) else {
            throw MirrorError.phoneNotConnected(detail: "capture produced an empty image")
        }
        counter += 1
        return Screenshot(full: full, model: model, geometry: g, frameID: counter)
    }
}
