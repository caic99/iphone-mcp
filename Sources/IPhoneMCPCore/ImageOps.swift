import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

public enum ImageOps {
    /// Crop a window capture to a rect given in window points.
    public static func crop(_ image: CGImage, windowPointRect r: CGRect, pixelsPerPoint s: Double) -> CGImage? {
        let px = CGRect(x: (r.minX * s).rounded(), y: (r.minY * s).rounded(),
                        width: (r.width * s).rounded(), height: (r.height * s).rounded())
            .intersection(CGRect(x: 0, y: 0, width: image.width, height: image.height))
        guard !px.isEmpty else { return nil }
        return image.cropping(to: px)
    }

    public static func resize(_ image: CGImage, width: Int, height: Int) -> CGImage? {
        guard width > 0, height > 0,
              let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.interpolationQuality = .high
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return ctx.makeImage()
    }

    public static func png(_ image: CGImage) -> Data? {
        let data = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(dest, image, nil)
        return CGImageDestinationFinalize(dest) ? data as Data : nil
    }

    /// RGBA8 pixels, row 0 = top of the image.
    public static func rgba(_ image: CGImage) -> [UInt8] {
        let w = image.width, h = image.height
        var buf = [UInt8](repeating: 0, count: w * h * 4)
        buf.withUnsafeMutableBytes { raw in
            let ctx = CGContext(data: raw.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        }
        return buf
    }

    /// Fraction of pixels whose summed |ΔR|+|ΔG|+|ΔB| exceeds `threshold`. Size mismatch → 1.
    public static func changedFraction(_ a: CGImage, _ b: CGImage, threshold: Int = 60) -> Double {
        guard a.width == b.width, a.height == b.height, a.width > 0, a.height > 0 else { return 1 }
        let pa = rgba(a), pb = rgba(b)
        var changed = 0
        for i in stride(from: 0, to: pa.count, by: 4) {
            let d = abs(Int(pa[i]) - Int(pb[i])) + abs(Int(pa[i + 1]) - Int(pb[i + 1])) + abs(Int(pa[i + 2]) - Int(pb[i + 2]))
            if d > threshold { changed += 1 }
        }
        return Double(changed) / Double(a.width * a.height)
    }
}
