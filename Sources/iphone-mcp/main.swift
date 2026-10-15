import AppKit
import IPhoneMCPCore
import MCP

_ = NSApplication.shared   // required: initialises the window-server connection (CGS) for capture

let argv = Array(CommandLine.arguments.dropFirst())
switch argv.first {
case "status":
    print(Status.json())
case "shot":
    let out = argv.count > 1 ? argv[1] : "shot.png"
    do {
        let t = try MirrorWindow.locate()
        let s = try await Capturer().capture(t)
        try ImageOps.png(argv.contains("--full") ? s.full : s.model)!.write(to: URL(fileURLWithPath: out))
        print("wrote \(out) \(s.model.width)x\(s.model.height) (full \(s.full.width)x\(s.full.height))")
    } catch let e as MirrorError {
        print("\(e.code): \(e.message)"); exit(1)
    }
case "call":
    guard argv.count >= 2 else { print("usage: iphone-mcp call <tool> ['<json args>']"); exit(2) }
    let json = argv.count > 2 ? argv[2] : "{}"
    let args = (try? JSONDecoder().decode([String: Value].self, from: Data(json.utf8))) ?? [:]
    let tools = PhoneTools(readOnly: ProcessInfo.processInfo.environment["IPHONE_MCP_READONLY"] == "1")
    let r = await tools.call(argv[1], args)
    for (i, c) in r.content.enumerated() {
        switch c {
        case .text(let t, _, _): print(t)
        case .image(let data, _, _, _):
            let path = NSTemporaryDirectory() + "iphone-mcp-call-\(i).png"
            try? Data(base64Encoded: data)?.write(to: URL(fileURLWithPath: path))
            print("[image] \(path)")
        default: break
        }
    }
    exit(r.isError == true ? 1 : 0)
case "selftest":
    exit(await runSelfTest())
case nil, "serve":
    let tools = PhoneTools(readOnly: ProcessInfo.processInfo.environment["IPHONE_MCP_READONLY"] == "1")
    let server = Server(name: "iphone-mcp", version: "0.1.0", instructions: PhoneTools.instructions,
                        capabilities: .init(tools: .init(listChanged: false)))
    Task.detached(priority: .background) {   // Vision's first run loads models (~13 s); pay it before the first OCR call
        if let ctx = CGContext(data: nil, width: 64, height: 64, bitsPerComponent: 8, bytesPerRow: 0,
                               space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
           let img = ctx.makeImage() { _ = try? OCR.recognize(img, outputScale: 1) }
    }
    try await server.start(transport: StdioTransport())
    await server.withMethodHandler(ListTools.self) { _ in .init(tools: tools.definitions) }
    await server.withMethodHandler(CallTool.self) { params in await tools.call(params.name, params.arguments ?? [:]) }
    await server.waitUntilCompleted()
default:
    FileHandle.standardError.write("usage: iphone-mcp [serve|status|shot <file> [--full]|call <tool> [json]|selftest]\n".data(using: .utf8)!)
    exit(2)
}
