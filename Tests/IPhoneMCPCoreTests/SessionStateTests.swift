import Testing
@testable import IPhoneMCPCore

@Suite struct SessionStateTests {
    @Test func noNativeUIMeansLiveStream() { #expect(SessionState.from(nodes: [], rootReadable: true) == .ready) }

    @Test func nativeUIMeansBlockedWithTexts() {
        #expect(SessionState.from(nodes: [("AXStaticText", "iPhone in Use"), ("AXButton", ""), ("AXStaticText", "  ")], rootReadable: true)
                == .blocked(["iPhone in Use"]))
    }

    @Test func blockedEvenWithoutReadableText() {
        #expect(SessionState.from(nodes: [("AXButton", "")], rootReadable: true) == .blocked([]))
    }

    @Test func unreadableWindowFailsClosed() {
        #expect(SessionState.from(nodes: [], rootReadable: false) == .blocked(["cannot verify the phone stream"]))
    }
}
