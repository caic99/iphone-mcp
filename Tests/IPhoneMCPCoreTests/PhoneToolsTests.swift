import MCP
import Testing
@testable import IPhoneMCPCore

@Suite struct PhoneToolsTests {
    @Test func fullToolSurface() {
        let names = Set(PhoneTools(readOnly: false).definitions.map(\.name))
        #expect(names == ["screenshot", "screenshot_text", "tap_text", "tap", "long_press", "swipe", "drag",
                          "type_text", "press_key", "home", "app_switcher", "spotlight", "launch_app", "scroll", "status"])
    }

    @Test func readOnlySurface() {
        #expect(Set(PhoneTools(readOnly: true).definitions.map(\.name)) == ["screenshot", "screenshot_text", "status"])
    }

    @Test func everySchemaIsAnObject() {
        for t in PhoneTools(readOnly: false).definitions {
            #expect(t.inputSchema.objectValue?["type"] == .string("object"), "\(t.name)")
        }
    }

    @Test func readOnlyRejectsInputTools() async {
        let r = await PhoneTools(readOnly: true, systemAccess: false).call("tap", ["x": .int(1), "y": .int(1)])
        #expect(r.isError == true)
        #expect(PhoneTools.firstText(r).hasPrefix("INVALID_ARGUMENT"))
    }

    @Test func badArgumentsFailBeforeTouchingTheSystem() async {
        let r = await PhoneTools(readOnly: false, systemAccess: false).call("press_key", ["key": .string("f13")])
        #expect(r.isError == true)
        #expect(PhoneTools.firstText(r).hasPrefix("INVALID_ARGUMENT"))
    }

    @Test func overlongTextIsRejectedBeforeTyping() async {
        let r = await PhoneTools(readOnly: false, systemAccess: false).call("type_text", ["text": .string(String(repeating: "a", count: 2001))])
        #expect(r.isError == true)
        #expect(PhoneTools.firstText(r).hasPrefix("INVALID_ARGUMENT"))
    }

    @Test func validationOnlyModeNeverReachesTheSystem() async {
        let r = await PhoneTools(readOnly: false, systemAccess: false).call("home", [:])
        #expect(r.isError == true)
        #expect(PhoneTools.firstText(r).contains("system access disabled"))
    }

    @Test func scrollRejectsZeroAndHugeDistances() async {
        let tools = PhoneTools(readOnly: false, systemAccess: false)
        for dy in [0, 5000, -5000] {
            let r = await tools.call("scroll", ["x": .int(100), "y": .int(300), "dy": .int(dy)])
            #expect(PhoneTools.firstText(r).hasPrefix("INVALID_ARGUMENT"), "dy=\(dy)")
        }
    }

    @Test func actionToolsTakeReturnModeNotReturnScreenshot() {
        for t in PhoneTools(readOnly: false).definitions where !["screenshot", "screenshot_text", "status"].contains(t.name) {
            let props = t.inputSchema.objectValue?["properties"]?.objectValue
            #expect(props?["return"] != nil, "\(t.name)")
            #expect(props?["return_screenshot"] == nil, "\(t.name)")
        }
    }

    @Test func badReturnModeIsInvalid() async {
        let r = await PhoneTools(readOnly: false, systemAccess: false).call("home", ["return": .string("png")])
        #expect(PhoneTools.firstText(r).hasPrefix("INVALID_ARGUMENT"))
    }
}
