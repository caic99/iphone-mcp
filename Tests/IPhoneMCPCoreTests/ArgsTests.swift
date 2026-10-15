import MCP
import Testing
@testable import IPhoneMCPCore

@Suite struct ArgsTests {
    @Test func numbersAcceptIntAndDouble() throws {
        let a = Args(["x": .int(10), "y": .double(2.5)])
        #expect(try a.double("x") == 10 && a.double("y") == 2.5)
    }

    @Test func missingRequiredIsInvalid() {
        #expect(throws: MirrorError.invalidArgument("missing required argument \"x\"")) { try Args([:]).double("x") }
    }

    @Test func stringsAreNotNumbers() {
        #expect(throws: MirrorError.invalidArgument("\"x\" must be a number")) { try Args(["x": .string("100")]).double("x") }
    }

    @Test func nanIsRejected() {
        #expect(throws: MirrorError.self) { try Args(["x": .double(.nan)]).double("x") }
    }

    @Test func intDefaultAndRange() throws {
        #expect(try Args([:]).int("d", default: 250, range: 0...3000) == 250)
        #expect(try Args(["d": .null]).int("d", default: 250, range: 0...3000) == 250)
        #expect(throws: MirrorError.invalidArgument("\"d\" must be an integer in 0...3000")) {
            try Args(["d": .int(99999)]).int("d", default: 250, range: 0...3000)
        }
        #expect(throws: MirrorError.self) { try Args(["d": .int(-5)]).int("d", default: 250, range: 0...3000) }
        #expect(throws: MirrorError.self) { try Args(["d": .double(1.5)]).int("d", default: 250, range: 0...3000) }
    }

    @Test func boolAndString() throws {
        #expect(try Args([:]).bool("return_screenshot", default: true) == true)
        #expect(try Args(["return_screenshot": .bool(false)]).bool("return_screenshot", default: true) == false)
        #expect(try Args(["text": .string("hi")]).string("text") == "hi")
        #expect(throws: MirrorError.self) { try Args(["text": .int(1)]).string("text") }
        #expect(try Args([:]).optionalInt("occurrence") == nil)
    }

    @Test func choiceAcceptsOnlyAllowedValues() throws {
        let allowed = ["text", "image", "both", "none"]
        #expect(try Args([:]).choice("return", default: "text", allowed: allowed) == "text")
        #expect(try Args(["return": .string("image")]).choice("return", default: "text", allowed: allowed) == "image")
        #expect(throws: MirrorError.invalidArgument("\"return\" must be one of: text, image, both, none")) {
            try Args(["return": .string("png")]).choice("return", default: "text", allowed: allowed)
        }
    }
}
