import AppKit
import CoreText
import Testing
@testable import IPhoneMCPCore

@Suite struct OCRTests {
    @Test func readingOrderGroupsRowsLeftToRight() {
        let a = line("A", 200, 10), b = line("B", 10, 14), c = line("C", 5, 100)
        #expect(OCR.readingOrder([c, a, b]).map(\.text) == ["B", "A", "C"])
    }

    @Test func recognizesEnglishAndChineseWithScaledBoxes() throws {
        // 800×400 white image (a "2×" capture), text baseline 100 px from the top.
        let img = TestImages.make(width: 800, height: 400) { ctx in
            ctx.setFillColor(red: 1, green: 1, blue: 1, alpha: 1); ctx.fill(CGRect(x: 0, y: 0, width: 800, height: 400))
            // Undo the helper's flip for text drawing so glyphs are upright.
            ctx.saveGState(); ctx.translateBy(x: 0, y: 400); ctx.scaleBy(x: 1, y: -1)
            let attr = NSAttributedString(string: "Settings   设置", attributes: [
                .font: NSFont.systemFont(ofSize: 48), .foregroundColor: NSColor.black])
            ctx.textPosition = CGPoint(x: 40, y: 300)
            CTLineDraw(CTLineCreateWithAttributedString(attr), ctx)
            ctx.restoreGState()
        }
        let lines = try OCR.recognize(img, outputScale: 2)
        let all = lines.map(\.text).joined(separator: " ")
        #expect(all.contains("Settings"))
        #expect(all.contains("设置"))
        let first = try #require(lines.first)
        #expect((10...30).contains(first.x))   // 40 px / 2 ≈ 20 pt
        #expect((15...50).contains(first.y))   // top of 48 px glyphs at ~55 px / 2
    }

    @Test func compactIsOneElementPerLineWithBox() {
        #expect(OCR.compact([line("iOS版本", 28, 167, w: 57, h: 17), line("27.0>", 285, 168, w: 43, h: 16)])
                == "iOS版本 @28,167,57,17\n27.0> @285,168,43,16")
        #expect(OCR.compact([]) == "(no text recognised)")
    }
}
