import CoreGraphics
import Testing
@testable import IPhoneMCPCore

@Suite struct GeometryTests {
    let g = PhoneGeometry(windowFrame: CGRect(x: 509, y: 56, width: 380, height: 837))

    @Test func screenSizeExcludesBezel() {
        #expect(g.screenSize == CGSize(width: 364, height: 791))
        #expect(g.screenRectInWindow == CGRect(x: 8, y: 38, width: 364, height: 791))
    }

    @Test func originMapsToScreenTopLeft() throws {
        #expect(try g.toGlobal(x: 0, y: 0) == CGPoint(x: 517, y: 94))
        #expect(try g.toGlobal(x: 100, y: 200) == CGPoint(x: 617, y: 294))
    }

    @Test func movedWindowUsesNewFrame() throws {
        let moved = PhoneGeometry(windowFrame: CGRect(x: 438, y: 57, width: 380, height: 836))
        #expect(try moved.toGlobal(x: 100, y: 200) == CGPoint(x: 546, y: 295))
    }

    @Test(arguments: [(-1.0, 0.0), (0.0, -0.5), (364.0, 10.0), (10.0, 791.0), (Double.nan, 5.0), (5.0, .infinity)])
    func rejectsOutOfBounds(_ p: (Double, Double)) {
        #expect(throws: MirrorError.self) { try g.toGlobal(x: p.0, y: p.1) }
    }

    @Test func outOfBoundsErrorCarriesScreenSize() {
        #expect(throws: MirrorError.outOfBounds(x: 400, y: 1, width: 364, height: 791)) { try g.toGlobal(x: 400, y: 1) }
    }

    @Test func titleBarToolbarIsOutsideTheScreen() {
        #expect(!g.screenContains(global: CGPoint(x: 600, y: 70)))    // hover toolbar in the 38 pt title inset
        #expect(g.screenContains(global: CGPoint(x: 600, y: 400)))    // centre of a lock / "in use" sheet
        #expect(!g.screenContains(global: CGPoint(x: 100, y: 400)))   // left of the window
    }
}
