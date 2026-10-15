import Testing
@testable import IPhoneMCPCore

func line(_ t: String, _ x: Int, _ y: Int, w: Int = 40, h: Int = 20) -> TextLine {
    TextLine(text: t, x: x, y: y, w: w, h: h, confidence: 1)
}

@Suite struct TextMatcherTests {
    let lines = [line("设置", 10, 10), line("通用", 10, 60), line("通用设置", 10, 110), line("Wi-Fi", 10, 160)]

    @Test func exactMatchWinsOverSubstring() throws {
        #expect(try TextMatcher.find("通用", in: lines, occurrence: nil) == lines[1])
    }

    @Test func trimsQueryAndCandidates() throws {
        #expect(try TextMatcher.find("  Wi-Fi ", in: [line(" Wi-Fi", 0, 0)], occurrence: nil).text == " Wi-Fi")
    }

    @Test func caseInsensitiveSubstringFallback() throws {
        #expect(try TextMatcher.find("wi-f", in: lines, occurrence: nil) == lines[3])
    }

    @Test func ambiguousSubstringListsCandidates() {
        #expect(throws: MirrorError.textAmbiguous(query: "设", matches: ["设置 @ (30,20)", "通用设置 @ (30,120)"])) {
            try TextMatcher.find("设", in: lines, occurrence: nil)
        }
    }

    @Test func occurrencePicksOneBased() throws {
        #expect(try TextMatcher.find("设", in: lines, occurrence: 2) == lines[2])
    }

    @Test func occurrenceOutOfRange() {
        #expect(throws: MirrorError.self) { try TextMatcher.find("设", in: lines, occurrence: 3) }
        #expect(throws: MirrorError.self) { try TextMatcher.find("设", in: lines, occurrence: 0) }
    }

    @Test func notFound() {
        #expect(throws: MirrorError.textNotFound("蓝牙")) { try TextMatcher.find("蓝牙", in: lines, occurrence: nil) }
    }

    @Test func emptyQueryIsInvalid() {
        #expect(throws: MirrorError.invalidArgument("text must not be empty")) { try TextMatcher.find("  ", in: lines, occurrence: nil) }
    }
}
