import AppKit
import IPhoneMCPCore
import MCP

/// Harmless on-device check: Spotlight, typing, OCR, scrolling the results list, Home.
/// Never taps icons or swipes on the Home Screen.
func runSelfTest() async -> Int32 {
    let tools = PhoneTools(readOnly: false)
    var failures: Int32 = 0
    let frontBefore = MirrorWindow.frontmostOwnerPID()
    let cursorBefore = CGEvent(source: nil)?.location ?? .zero

    func step(_ label: String, _ name: String, _ args: [String: Value] = [:],
              check: (CallTool.Result) -> Bool = { $0.isError != true }) async {
        let t0 = Date()
        let r = await tools.call(name, args)
        let ms = Int(Date().timeIntervalSince(t0) * 1000)
        let ok = check(r)
        if !ok { failures += 1 }
        print("\(ok ? "PASS" : "FAIL")  \(label)  \(ms) ms  \(ok ? "" : PhoneTools.firstText(r))")
    }
    func hasText(_ s: String) -> (CallTool.Result) -> Bool {
        { $0.isError != true && PhoneTools.firstText($0).localizedCaseInsensitiveContains(s) }
    }

    print("selftest: keep your hands off the mouse and keyboard for ~20 s")
    await step("status is ready", "status", check: hasText("\"session\":\"ready\""))
    await step("screenshot", "screenshot")
    await step("open Spotlight", "spotlight")
    await step("type 'test'", "type_text", ["text": .string("test")])
    await step("OCR sees 'test'", "screenshot_text", check: hasText("test"))
    // Scrolling must actually move the content: compare OCR text before and after.
    let ocrBefore = PhoneTools.firstText(await tools.call("screenshot_text", [:]))
    await step("scroll results down", "scroll", ["x": .int(182), "y": .int(300), "dy": .int(-300), "return": .string("none")])
    let ocrAfter = PhoneTools.firstText(await tools.call("screenshot_text", [:]))
    let moved = ocrBefore != ocrAfter
    if !moved { failures += 1 }
    print("\(moved ? "PASS" : "FAIL")  scrolling changed the screen")
    await step("scroll results back up", "scroll", ["x": .int(182), "y": .int(300), "dy": .int(300), "return": .string("none")])
    for _ in 0..<4 { await step("delete", "press_key", ["key": .string("delete"), "return": .string("none")]) }
    await step("home", "home")
    await step("out-of-bounds rejected", "tap", ["x": .int(9999), "y": .int(1)],
               check: { $0.isError == true && PhoneTools.firstText($0).hasPrefix("OUT_OF_BOUNDS") })

    let frontAfter = MirrorWindow.frontmostOwnerPID()
    let c = CGEvent(source: nil)?.location ?? .zero
    // Cursor drift is informational: anything you do with the mouse during the run also moves it.
    let restored = frontAfter == frontBefore
    if !restored { failures += 1 }
    print("\(restored ? "PASS" : "FAIL")  frontmost app restored (pid \(frontBefore ?? -1) → \(frontAfter ?? -1))")
    print("INFO  cursor moved \(Int(hypot(c.x - cursorBefore.x, c.y - cursorBefore.y))) pt over the whole run (0 if you kept hands off)")
    print(failures == 0 ? "ALL PASS" : "\(failures) FAILURE(S)")
    return failures
}
