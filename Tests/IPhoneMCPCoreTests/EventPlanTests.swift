import CoreGraphics
import Testing
@testable import IPhoneMCPCore

@Suite struct EventPlanTests {
    let c = CGPoint(x: 0, y: 0), a = CGPoint(x: 100, y: 500), b = CGPoint(x: 100, y: 300)

    @Test func tapApproachesThenDownUpAtSamePoint() {
        let s = EventPlan.tap(a, from: c)
        let moves = s.compactMap { if case .move(let p) = $0 { p } else { nil } }
        #expect(moves.count == 4 && moves.last == a)
        #expect(Array(s.suffix(3)) == [.down(a), .sleep(ms: 60), .up(a)])
    }

    @Test func swipeStartsMovingImmediatelyAfterDown() {
        let s = EventPlan.swipe(a, b, durationMs: 250, from: c)
        let i = s.firstIndex(of: .down(a))!
        guard case .drag(let first) = s[i + 1] else { Issue.record("step after down must be .drag"); return }
        #expect(first.x == 100 && abs(first.y - (500 - 200.0 / 15)) < 1e-9)   // n = max(8, 250/16=15)
        #expect(s.last == .up(b))
        #expect(s.contains(.drag(b)))
    }

    @Test func swipeZeroDurationStillHasEightSteps() {
        let s = EventPlan.swipe(a, b, durationMs: 0, from: c)
        #expect(s.filter { if case .drag = $0 { true } else { false } }.count == 8)
    }

    @Test func dragHoldsBeforeMoving() {
        let s = EventPlan.drag(a, b, holdMs: 600, durationMs: 500, from: c)
        let i = s.firstIndex(of: .down(a))!
        #expect(s[i + 1] == .sleep(ms: 600))
        #expect(Array(s.suffix(2)) == [.sleep(ms: 100), .up(b)])
    }

    @Test func longPress() {
        #expect(Array(EventPlan.longPress(a, ms: 800, from: c).suffix(3)) == [.down(a), .sleep(ms: 800), .up(a)])
    }

    @Test func commandComboHoldsRealModifierAndClearsFlagOnRelease() {
        let cmd = CGEventFlags.maskCommand.rawValue
        #expect(EventPlan.keyCombo(KeyCode.three, [.command]) == [
            .key(code: 55, down: true, flags: cmd), .sleep(ms: 20),
            .key(code: 20, down: true, flags: cmd), .sleep(ms: 20),
            .key(code: 20, down: false, flags: cmd), .sleep(ms: 20),
            .key(code: 55, down: false, flags: 0), .sleep(ms: 20),
        ])
    }

    @Test func typeTextKeepsGraphemesIntactAndMapsNewline() {
        let s = EventPlan.typeText("中a😀👍🏽\n")
        let texts = s.compactMap { if case .text(let u) = $0 { u } else { nil } }
        #expect(texts == [Array("中".utf16), Array("a".utf16), Array("😀".utf16), Array("👍🏽".utf16)])
        #expect(texts[2].count == 2 && texts[3].count == 4)
        #expect(s.contains(.key(code: 36, down: true, flags: 0)))
    }

    @Test func namedKeys() {
        #expect(KeyCode.named["return"] == 36 && KeyCode.named["delete"] == 51 && KeyCode.named["escape"] == 53)
        #expect(KeyCode.named["tab"] == 48 && KeyCode.named["left"] == 123 && KeyCode.named["right"] == 124)
        #expect(KeyCode.named["down"] == 125 && KeyCode.named["up"] == 126)
    }

    @Test func scrollMovesOverPointThenWheelsInChunksSummingToDy() {
        let s = EventPlan.scroll(at: a, dy: -305, from: c)
        let moves = s.compactMap { if case .move(let p) = $0 { p } else { nil } }
        #expect(moves.last == a)
        let wheels = s.compactMap { if case .scroll(let p, let d) = $0 { (p, d) } else { nil } }
        #expect(wheels.count == 10)
        #expect(wheels.allSatisfy { $0.0 == a })
        #expect(wheels.map(\.1).reduce(0, +) == -305)
        #expect(!s.contains { if case .down = $0 { true } else { false } })   // never a touch
    }

    @Test func launchAppClearsSpotlightBeforeTyping() {
        let s = EventPlan.launchApp("设置")
        let cmd = CGEventFlags.maskCommand.rawValue
        let openSpotlight = s.firstIndex(of: .key(code: KeyCode.three, down: true, flags: cmd))!
        let selectAll = s.firstIndex(of: .key(code: KeyCode.a, down: true, flags: cmd))!
        let delete = s.firstIndex(of: .key(code: 51, down: true, flags: 0))!
        let typed = s.firstIndex(of: .text(Array("设".utf16)))!
        let enter = s.lastIndex(of: .key(code: KeyCode.returnKey, down: true, flags: 0))!
        #expect(openSpotlight < selectAll && selectAll < delete && delete < typed && typed < enter)
    }
}
