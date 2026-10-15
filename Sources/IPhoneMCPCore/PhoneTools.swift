import AppKit
import MCP

public final class PhoneTools {
    public static let instructions = """
        Controls the user's real iPhone through macOS iPhone Mirroring. All coordinates are pixels of the 1x \
        screenshot (origin = top-left of the phone screen). Each input action briefly takes over the Mac's cursor \
        and focus. Ask the user before paying, purchasing, sending messages/emails, or deleting anything. \
        Prefer tap_text when the target has a visible label.
        """

    static let readOnlyNames: Set<String> = ["screenshot", "screenshot_text", "status"]

    public static let maxTextLength = 2000

    public let definitions: [Tool]
    let systemAccess: Bool
    let takeover = Takeover()
    let capturer = Capturer()
    let lock = AsyncLock()

    /// `systemAccess: false` stops every call after argument validation — unit tests use it so a
    /// validation gap can never reach the user's real phone.
    public init(readOnly: Bool, systemAccess: Bool = true) {
        let all = Self.allDefinitions()
        definitions = readOnly ? all.filter { Self.readOnlyNames.contains($0.name) } : all
        self.systemAccess = systemAccess
    }

    // MARK: schema helpers

    static func schema(_ props: [(String, String, String)], required: [String] = [], screenshotFlag: Bool = true) -> Value {
        var p: [String: Value] = [:]
        for (name, type, desc) in props { p[name] = .object(["type": .string(type), "description": .string(desc)]) }
        if screenshotFlag {
            p["return"] = .object(["type": .string("string"), "enum": .array(ReturnMode.allCases.map { .string($0.rawValue) }),
                "description": .string("What to return once the screen settles: \"text\" (default, compact OCR lines \"label @x,y,w,h\"; the image is added automatically when the screen has almost no text), \"image\" (when you need icons, toggle states, photos or layout), \"both\", or \"none\".")])
        }
        return .object(["type": .string("object"), "properties": .object(p), "required": .array(required.map { .string($0) })])
    }

    static func allDefinitions() -> [Tool] {
        let xy = [("x", "number", "X in 1x screenshot pixels"), ("y", "number", "Y in 1x screenshot pixels")]
        return [
            Tool(name: "screenshot", description: "Capture the phone screen as PNG. Use when text is not enough (icons, toggle states, images, layout); otherwise prefer screenshot_text. Coordinates for all tools are in the 1x image's pixels even when scale=2.",
                 inputSchema: schema([("scale", "integer", "1 (default) or 2 for fine print")], screenshotFlag: false)),
            Tool(name: "screenshot_text", description: "OCR the phone screen: one line per text element, \"label @x,y,w,h\" in 1x coordinates (centre = x+w/2, y+h/2). Cheapest way to read the screen.",
                 inputSchema: schema([], screenshotFlag: false)),
            Tool(name: "tap_text", description: "Find on-screen text by OCR (exact, then case-insensitive substring) and tap its centre. Errors if absent or ambiguous; pass occurrence (1-based) to choose.",
                 inputSchema: schema([("text", "string", "Label to tap"), ("occurrence", "integer", "1-based match index")], required: ["text"])),
            Tool(name: "tap", description: "Tap at (x, y).", inputSchema: schema(xy, required: ["x", "y"])),
            Tool(name: "long_press", description: "Press and hold at (x, y).",
                 inputSchema: schema(xy + [("duration_ms", "integer", "Hold time, 100-5000, default 800")], required: ["x", "y"])),
            Tool(name: "scroll", description: "Scroll the list/page under (x, y) by dy pixels with the scroll wheel. Negative dy scrolls down (reveals content below). Use this, not swipe, for lists. Distance is approximate (iOS adds momentum); check the returned screenshot.",
                 inputSchema: schema(xy + [("dy", "integer", "Pixels, -3000..3000, non-zero; negative = down")], required: ["x", "y", "dy"])),
            Tool(name: "swipe", description: "Flick/page gesture from (x1,y1) to (x2,y2) — Home Screen pages, carousels, swipe-to-go-back. Does NOT scroll lists (use scroll). Movement starts immediately so it never becomes a long-press.",
                 inputSchema: schema([("x1", "number", "Start X"), ("y1", "number", "Start Y"), ("x2", "number", "End X"), ("y2", "number", "End Y"),
                                      ("duration_ms", "integer", "0-3000, default 250")], required: ["x1", "y1", "x2", "y2"])),
            Tool(name: "drag", description: "Long-press at (x1,y1), then move to (x2,y2) and release — for moving icons, sliders, reordering.",
                 inputSchema: schema([("x1", "number", "Start X"), ("y1", "number", "Start Y"), ("x2", "number", "End X"), ("y2", "number", "End Y"),
                                      ("hold_ms", "integer", "300-3000, default 600"), ("duration_ms", "integer", "0-5000, default 500")],
                                     required: ["x1", "y1", "x2", "y2"])),
            Tool(name: "type_text", description: "Type text into the focused field (any language/emoji; \\n presses Return). Tap a field first.",
                 inputSchema: schema([("text", "string", "Text to type")], required: ["text"])),
            Tool(name: "press_key", description: "Press a key: return, delete, escape, tab, up, down, left, right.",
                 inputSchema: schema([("key", "string", "Key name")], required: ["key"])),
            Tool(name: "home", description: "Go to the Home Screen.", inputSchema: schema([])),
            Tool(name: "app_switcher", description: "Open the App Switcher.", inputSchema: schema([])),
            Tool(name: "spotlight", description: "Open Spotlight search.", inputSchema: schema([])),
            Tool(name: "launch_app", description: "Open an app by name via Spotlight (opens the top hit).",
                 inputSchema: schema([("name", "string", "App name as shown on the phone")], required: ["name"])),
            Tool(name: "status", description: "Report whether iPhone Mirroring is running and live, window frame, and permissions.",
                 inputSchema: schema([], screenshotFlag: false)),
        ]
    }

    // MARK: content helpers

    static func text(_ s: String) -> Tool.Content { .text(text: s, annotations: nil, _meta: nil) }
    static func image(_ img: CGImage) -> Tool.Content {
        .image(data: (ImageOps.png(img) ?? Data()).base64EncodedString(), mimeType: "image/png", annotations: nil, _meta: nil)
    }
    public static func firstText(_ r: CallTool.Result) -> String {
        for c in r.content { if case .text(let t, _, _) = c { return t } }
        return ""
    }

    // MARK: dispatch

    public func call(_ name: String, _ arguments: [String: Value]) async -> CallTool.Result {
        let result: CallTool.Result
        do {
            guard definitions.contains(where: { $0.name == name }) else {
                throw MirrorError.invalidArgument("unknown or disabled tool \"\(name)\"")
            }
            // One tool call at a time: the SDK runs requests concurrently and gestures must not interleave.
            result = try await lock.withLock { try await dispatch(name, Args(arguments)) }
        } catch let e as MirrorError {
            result = .init(content: [Self.text("\(e.code): \(e.message)")], isError: true)
        } catch {
            result = .init(content: [Self.text("INTERNAL: \(error)")], isError: true)
        }
        Log.action(name, keys: Array(arguments.keys), outcome: result.isError == true ? "error" : "ok")
        return result
    }

    func dispatch(_ name: String, _ a: Args) async throws -> CallTool.Result {
        if name == "status" { return .init(content: [Self.text(Status.json())]) }

        // Validate arguments and build the plan before touching the system.
        enum Plan { case shot(Int), ocr, tapText(String, Int?), steps(String, (PhoneGeometry, CGPoint) throws -> [InputStep]) }
        let plan: Plan
        switch name {
        case "screenshot": plan = .shot(try a.int("scale", default: 1, range: 1...2))
        case "screenshot_text": plan = .ocr
        case "tap_text": plan = .tapText(try a.string("text"), try a.optionalInt("occurrence"))
        case "tap":
            let x = try a.double("x"), y = try a.double("y")
            plan = .steps("tapped (\(x), \(y))") { g, c in EventPlan.tap(try g.toGlobal(x: x, y: y), from: c) }
        case "long_press":
            let x = try a.double("x"), y = try a.double("y"), ms = try a.int("duration_ms", default: 800, range: 100...5000)
            plan = .steps("long-pressed (\(x), \(y)) for \(ms) ms") { g, c in EventPlan.longPress(try g.toGlobal(x: x, y: y), ms: ms, from: c) }
        case "scroll":
            let x = try a.double("x"), y = try a.double("y"), dy = try a.int("dy", default: 0, range: -3000...3000)
            guard dy != 0 else { throw MirrorError.invalidArgument("\"dy\" must be non-zero") }
            plan = .steps("scrolled \(dy) px at (\(x), \(y))") { g, c in EventPlan.scroll(at: try g.toGlobal(x: x, y: y), dy: dy, from: c) }
        case "swipe", "drag":
            let x1 = try a.double("x1"), y1 = try a.double("y1"), x2 = try a.double("x2"), y2 = try a.double("y2")
            if name == "swipe" {
                let d = try a.int("duration_ms", default: 250, range: 0...3000)
                plan = .steps("swiped (\(x1), \(y1)) → (\(x2), \(y2))") { g, c in
                    EventPlan.swipe(try g.toGlobal(x: x1, y: y1), try g.toGlobal(x: x2, y: y2), durationMs: d, from: c)
                }
            } else {
                let hold = try a.int("hold_ms", default: 600, range: 300...3000), d = try a.int("duration_ms", default: 500, range: 0...5000)
                plan = .steps("dragged (\(x1), \(y1)) → (\(x2), \(y2))") { g, c in
                    EventPlan.drag(try g.toGlobal(x: x1, y: y1), try g.toGlobal(x: x2, y: y2), holdMs: hold, durationMs: d, from: c)
                }
            }
        case "type_text":
            let s = try a.string("text")
            guard !s.isEmpty, s.count <= Self.maxTextLength else {
                throw MirrorError.invalidArgument("text must be 1...\(Self.maxTextLength) characters")
            }
            plan = .steps("typed \(s.count) characters") { _, _ in EventPlan.typeText(s) }
        case "press_key":
            let k = try a.string("key").lowercased()
            guard let code = KeyCode.named[k] else {
                throw MirrorError.invalidArgument("unknown key \"\(k)\"; use one of \(KeyCode.named.keys.sorted().joined(separator: ", "))")
            }
            plan = .steps("pressed \(k)") { _, _ in EventPlan.keyCombo(code) }
        case "home": plan = .steps("went home") { _, _ in EventPlan.keyCombo(KeyCode.one, [.command]) }
        case "app_switcher": plan = .steps("opened app switcher") { _, _ in EventPlan.keyCombo(KeyCode.two, [.command]) }
        case "spotlight": plan = .steps("opened Spotlight") { _, _ in EventPlan.keyCombo(KeyCode.three, [.command]) }
        case "launch_app":
            let app = try a.string("name")
            guard !app.isEmpty, app.count <= 100 else { throw MirrorError.invalidArgument("name must be 1...100 characters") }
            plan = .steps("launched \"\(app)\" via Spotlight") { _, _ in EventPlan.launchApp(app) }
        default: throw MirrorError.invalidArgument("unknown tool \"\(name)\"")
        }
        let mode = ReturnMode(rawValue: try a.choice("return", default: "text", allowed: ReturnMode.allCases.map(\.rawValue)))!

        guard systemAccess else { throw MirrorError.invalidArgument("system access disabled (validation-only mode)") }
        try Permissions.require()
        let t = try MirrorWindow.locate()
        try MirrorWindow.requireLive(t)

        switch plan {
        case .shot(let scale):
            let s = try await capture(t)
            return .init(content: [Self.image(scale == 2 ? s.full : s.model),
                                   Self.text("{\"width\":\(s.model.width),\"height\":\(s.model.height),\"frame_id\":\(s.frameID),\"coordinates\":\"1x\"}")])
        case .ocr:
            let s = try await capture(t)
            let lines = try OCR.recognize(s.full, outputScale: s.pixelsPerPoint)
            return .init(content: [Self.text("screen \(s.model.width)x\(s.model.height)\n" + OCR.compact(lines))])
        case .tapText(let q, let occ):
            let s = try await capture(t)
            let line = try TextMatcher.find(q, in: try OCR.recognize(s.full, outputScale: s.pixelsPerPoint), occurrence: occ)
            return try await act(t, mode, "tapped \"\(line.text)\" at (\(line.centerX), \(line.centerY))") { fresh, c in
                EventPlan.tap(try fresh.geometry.toGlobal(x: Double(line.centerX), y: Double(line.centerY)), from: c)
            }
        case .steps(let summary, let build):
            return try await act(t, mode, summary) { fresh, c in try build(fresh.geometry, c) }
        }
    }

    /// ScreenCaptureKit can hang forever if the window goes away mid-capture (seen when Mirroring quit),
    /// and a hung request then blocks every later capture from the same binary until that process exits.
    func capture(_ t: MirrorTarget) async throws -> Screenshot {
        let capturer = self.capturer
        return try await withTimeout(seconds: 5, onTimeout: MirrorError.phoneNotConnected(
            detail: "screen capture timed out — if iPhone Mirroring is open and this repeats, restart the iphone MCP server (/mcp → reconnect)")) { try await capturer.capture(t) }
    }

    func act(_ t: MirrorTarget, _ mode: ReturnMode, _ summary: String,
             _ build: (MirrorTarget, CGPoint) throws -> [InputStep]) async throws -> CallTool.Result {
        try await takeover.run(on: t, build: build)
        guard mode != .none else { return .init(content: [Self.text("ok: \(summary)")]) }
        let s = try await settledScreenshot()
        let lines = mode == .image ? [] : try OCR.recognize(s.full, outputScale: s.pixelsPerPoint)
        let want = mode.resolve(ocrLines: lines.count)
        var header = "ok: \(summary); screen \(s.model.width)x\(s.model.height)"
        if want.text { header += "\n" + OCR.compact(lines) }
        return .init(content: [Self.text(header)] + (want.image ? [Self.image(s.model)] : []))
    }

    /// Wait for iOS to start reacting (stream latency), then sample every 100 ms until stable (max 1.5 s).
    func settledScreenshot() async throws -> Screenshot {
        try await Task.sleep(nanoseconds: 300_000_000)
        let t = try MirrorWindow.locate()
        var prev = try await capture(t)
        let deadline = Date().addingTimeInterval(1.5)
        while Date() < deadline {
            try await Task.sleep(nanoseconds: 100_000_000)
            let cur = try await capture(t)
            if Settle.isSettled(prev.model, cur.model) { return cur }
            prev = cur
        }
        return prev
    }
}
