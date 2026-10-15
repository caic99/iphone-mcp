import CoreGraphics
import Testing
@testable import IPhoneMCPCore

@Suite struct ImageOpsTests {
    @Test func cropUsesTopLeftOriginAndScale() {
        // 100×200 white image with a red 10×10 square in the top-left corner.
        let img = TestImages.make(width: 100, height: 200) { ctx in
            ctx.setFillColor(red: 1, green: 1, blue: 1, alpha: 1); ctx.fill(CGRect(x: 0, y: 0, width: 100, height: 200))
            ctx.setFillColor(red: 1, green: 0, blue: 0, alpha: 1); ctx.fill(CGRect(x: 0, y: 0, width: 10, height: 10))
        }
        let c = ImageOps.crop(img, windowPointRect: CGRect(x: 0, y: 0, width: 5, height: 5), pixelsPerPoint: 2)!
        #expect(c.width == 10 && c.height == 10)
        let px = ImageOps.rgba(c)
        #expect(px[0] > 200 && px[1] < 50 && px[2] < 50)              // first pixel red
        #expect(px[px.count - 4] > 200 && px[px.count - 3] < 50)      // last pixel red
    }

    @Test func resizeProducesRequestedSize() {
        let r = ImageOps.resize(TestImages.solid(width: 728, height: 1582, r: 0, g: 0, b: 1), width: 364, height: 791)!
        #expect(r.width == 364 && r.height == 791)
    }

    @Test func pngHasSignature() {
        let d = ImageOps.png(TestImages.solid(width: 4, height: 4, r: 0, g: 1, b: 0))!
        #expect(Array(d.prefix(4)) == [0x89, 0x50, 0x4E, 0x47])
    }

    @Test func changedFractionIdenticalIsZero() {
        let a = TestImages.solid(width: 20, height: 20, r: 0.5, g: 0.5, b: 0.5)
        #expect(ImageOps.changedFraction(a, a) == 0)
    }

    @Test func changedFractionHalf() {
        let a = TestImages.solid(width: 20, height: 20, r: 0, g: 0, b: 0)
        let b = TestImages.make(width: 20, height: 20) { ctx in
            ctx.setFillColor(red: 0, green: 0, blue: 0, alpha: 1); ctx.fill(CGRect(x: 0, y: 0, width: 20, height: 20))
            ctx.setFillColor(red: 1, green: 1, blue: 1, alpha: 1); ctx.fill(CGRect(x: 0, y: 0, width: 20, height: 10))
        }
        #expect(abs(ImageOps.changedFraction(a, b) - 0.5) < 0.001)
    }

    @Test func smallDeltaBelowThresholdIgnored() {
        let a = TestImages.solid(width: 10, height: 10, r: 0.50, g: 0.50, b: 0.50)
        let b = TestImages.solid(width: 10, height: 10, r: 0.52, g: 0.52, b: 0.52) // ~5 per channel → 15 < 60
        #expect(ImageOps.changedFraction(a, b) == 0)
    }

    @Test func sizeMismatchCountsAsFullyChanged() {
        #expect(ImageOps.changedFraction(TestImages.solid(width: 10, height: 10, r: 0, g: 0, b: 0),
                                         TestImages.solid(width: 10, height: 11, r: 0, g: 0, b: 0)) == 1)
    }

    @Test func settleThreshold() {
        let a = TestImages.solid(width: 100, height: 100, r: 0, g: 0, b: 0)
        let tiny = TestImages.make(width: 100, height: 100) { ctx in   // 40 px changed = 0.4 %
            ctx.setFillColor(red: 0, green: 0, blue: 0, alpha: 1); ctx.fill(CGRect(x: 0, y: 0, width: 100, height: 100))
            ctx.setFillColor(red: 1, green: 1, blue: 1, alpha: 1); ctx.fill(CGRect(x: 0, y: 0, width: 40, height: 1))
        }
        let big = TestImages.make(width: 100, height: 100) { ctx in    // 100 px changed = 1 %
            ctx.setFillColor(red: 0, green: 0, blue: 0, alpha: 1); ctx.fill(CGRect(x: 0, y: 0, width: 100, height: 100))
            ctx.setFillColor(red: 1, green: 1, blue: 1, alpha: 1); ctx.fill(CGRect(x: 0, y: 0, width: 100, height: 1))
        }
        #expect(Settle.isSettled(a, tiny))
        #expect(!Settle.isSettled(a, big))
    }
}
