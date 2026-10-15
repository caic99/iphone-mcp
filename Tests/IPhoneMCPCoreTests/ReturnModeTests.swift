import Testing
@testable import IPhoneMCPCore

@Suite struct ReturnModeTests {
    @Test func textOnlyWhenOCRFindsEnough() {
        #expect(ReturnMode.text.resolve(ocrLines: 10) == (text: true, image: false))
    }
    @Test func textFallsBackToImageWhenScreenHasLittleText() {
        #expect(ReturnMode.text.resolve(ocrLines: 2) == (text: true, image: true))
    }
    @Test func explicitModes() {
        #expect(ReturnMode.image.resolve(ocrLines: 50) == (text: false, image: true))
        #expect(ReturnMode.both.resolve(ocrLines: 50) == (text: true, image: true))
        #expect(ReturnMode.none.resolve(ocrLines: 0) == (text: false, image: false))
    }
}
