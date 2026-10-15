import CoreGraphics

enum TestImages {
    /// Draw with a CGContext whose origin is the TOP-left (flipped), like image pixel coordinates.
    static func make(width: Int, height: Int, draw: (CGContext) -> Void) -> CGImage {
        let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.translateBy(x: 0, y: CGFloat(height))
        ctx.scaleBy(x: 1, y: -1)
        draw(ctx)
        return ctx.makeImage()!
    }

    static func solid(width: Int, height: Int, r: CGFloat, g: CGFloat, b: CGFloat) -> CGImage {
        make(width: width, height: height) { ctx in
            ctx.setFillColor(red: r, green: g, blue: b, alpha: 1)
            ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        }
    }
}
