import CoreGraphics

public enum InputStep: Equatable, Sendable {
    case move(CGPoint)
    case down(CGPoint)
    case drag(CGPoint)
    case up(CGPoint)
    case key(code: UInt16, down: Bool, flags: UInt64)
    case text([UInt16])          // one grapheme, sent as one key down/up with a Unicode string
    case scroll(at: CGPoint, dy: Int32)   // pixel scroll-wheel; goes to the window under the cursor
    case sleep(ms: Int)
}

public enum Modifier: Sendable {
    case command, shift
    public var keyCode: UInt16 { self == .command ? 55 : 56 }
    public var flag: UInt64 { self == .command ? CGEventFlags.maskCommand.rawValue : CGEventFlags.maskShift.rawValue }
}

public enum KeyCode {
    public static let a: UInt16 = 0
    public static let one: UInt16 = 18, two: UInt16 = 19, three: UInt16 = 20, returnKey: UInt16 = 36
    public static let named: [String: UInt16] = [
        "return": 36, "delete": 51, "escape": 53, "tab": 48,
        "left": 123, "right": 124, "down": 125, "up": 126,
    ]
}

public enum EventPlan {
    static func lerp(_ a: CGPoint, _ b: CGPoint, _ t: Double) -> CGPoint {
        CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t)
    }

    /// Mirroring tracks relative pointer motion, so arrive with real mouseMoved events.
    static func approach(_ p: CGPoint, from c: CGPoint) -> [InputStep] {
        (1...4).flatMap { i -> [InputStep] in [.move(lerp(c, p, Double(i) / 4)), .sleep(ms: 8)] } + [.sleep(ms: 30)]
    }

    public static func tap(_ p: CGPoint, from c: CGPoint) -> [InputStep] {
        approach(p, from: c) + [.down(p), .sleep(ms: 60), .up(p)]
    }

    public static func longPress(_ p: CGPoint, ms: Int, from c: CGPoint) -> [InputStep] {
        approach(p, from: c) + [.down(p), .sleep(ms: ms), .up(p)]
    }

    static func path(_ a: CGPoint, _ b: CGPoint, durationMs: Int) -> [InputStep] {
        let n = max(8, durationMs / 16)
        return (1...n).flatMap { i -> [InputStep] in [.drag(lerp(a, b, Double(i) / Double(n))), .sleep(ms: durationMs / n)] }
    }

    /// Movement begins right after mouse-down so iOS never sees a long-press (a slow start turns into a long-press that picks up a Home Screen icon).
    public static func swipe(_ a: CGPoint, _ b: CGPoint, durationMs: Int, from c: CGPoint) -> [InputStep] {
        approach(a, from: c) + [.down(a)] + path(a, b, durationMs: durationMs) + [.up(b)]
    }

    /// Deliberate hold, then move — for icons and sliders.
    public static func drag(_ a: CGPoint, _ b: CGPoint, holdMs: Int, durationMs: Int, from c: CGPoint) -> [InputStep] {
        approach(a, from: c) + [.down(a), .sleep(ms: holdMs)] + path(a, b, durationMs: durationMs) + [.sleep(ms: 100), .up(b)]
    }

    /// Lists scroll with the wheel, not with drags (verified in Settings: drags did nothing, plain
    /// pixel wheel events scrolled both ways). Negative dy scrolls down.
    public static func scroll(at p: CGPoint, dy: Int, from c: CGPoint) -> [InputStep] {
        let n = 10, chunk = dy / n, rest = dy - chunk * n
        var s = approach(p, from: c) + [.sleep(ms: 60)]
        for i in 0..<n { s += [.scroll(at: p, dy: Int32(chunk + (i == n - 1 ? rest : 0))), .sleep(ms: 16)] }
        return s + [.sleep(ms: 250)]
    }

    /// Spotlight keeps text from last time, so select-all and delete before typing the name.
    public static func launchApp(_ name: String) -> [InputStep] {
        keyCombo(KeyCode.three, [.command]) + [.sleep(ms: 700)]
            + keyCombo(KeyCode.a, [.command]) + keyCombo(KeyCode.named["delete"]!)
            + typeText(name) + [.sleep(ms: 700)] + keyCombo(KeyCode.returnKey)
    }

    /// Modifiers are held as real keys; a release carries the flags *without* its own bit.
    public static func keyCombo(_ code: UInt16, _ mods: [Modifier] = []) -> [InputStep] {
        var s: [InputStep] = []
        var flags: UInt64 = 0
        for m in mods { flags |= m.flag; s += [.key(code: m.keyCode, down: true, flags: flags), .sleep(ms: 20)] }
        s += [.key(code: code, down: true, flags: flags), .sleep(ms: 20), .key(code: code, down: false, flags: flags), .sleep(ms: 20)]
        for m in mods.reversed() { flags &= ~m.flag; s += [.key(code: m.keyCode, down: false, flags: flags), .sleep(ms: 20)] }
        return s
    }

    public static func typeText(_ text: String) -> [InputStep] {
        var s: [InputStep] = []
        for ch in text {
            if ch == "\n" || ch == "\r\n" { s += keyCombo(KeyCode.returnKey) }
            else { s += [.text(Array(String(ch).utf16)), .sleep(ms: 15)] }
        }
        return s
    }
}
