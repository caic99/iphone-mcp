import CoreGraphics
import Testing
@testable import IPhoneMCPCore

@Suite struct WindowPickerTests {
    let app = "iPhone Mirroring"
    let phone = WindowCandidate(id: 1, title: "iPhone Mirroring", bounds: CGRect(x: 1071, y: 78, width: 376, height: 829))
    let welcome = WindowCandidate(id: 2, title: "Welcome to iPhone Mirroring", bounds: CGRect(x: 416, y: -837, width: 640, height: 662))
    let untitled = WindowCandidate(id: 3, title: "", bounds: CGRect(x: 0, y: 0, width: 376, height: 829))

    @Test func prefersTheWindowTitledLikeTheApp() {
        #expect(WindowPicker.pick([welcome, phone], appName: app) == phone)
    }

    @Test func neverPicksAWindowWithAnotherTitle() {
        #expect(WindowPicker.pick([welcome], appName: app) == nil)   // still connecting: no phone window yet
    }

    @Test func fallsBackToTheLargestUntitledWindow() {
        #expect(WindowPicker.pick([welcome, untitled], appName: app) == untitled)
    }

    @Test func ignoresSmallWindows() {
        let tiny = WindowCandidate(id: 4, title: "iPhone Mirroring", bounds: CGRect(x: 0, y: 0, width: 54, height: 54))
        #expect(WindowPicker.pick([tiny], appName: app) == nil)
    }
}
