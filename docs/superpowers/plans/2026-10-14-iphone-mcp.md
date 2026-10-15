# iphone-mcp Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A stdio MCP server (`iphone-mcp`) that lets Claude Code see and operate the user's iPhone through macOS iPhone Mirroring.

**Architecture:** One SwiftPM package: a library target `IPhoneMCPCore` (all logic; pure parts unit-tested) and a thin executable `iphone-mcp` (MCP stdio server plus `status`/`call`/`selftest` subcommands). Screenshots come from ScreenCaptureKit in the background; every input action is a short "takeover": activate Mirroring via Accessibility, post HID-tap CGEvents, restore the user's cursor and frontmost app.

**Tech Stack:** Swift 6.4 toolchain (language mode 5), macOS 15+, `modelcontextprotocol/swift-sdk` 0.12.1, ScreenCaptureKit, Vision, ApplicationServices (AX + CGEvent), Swift Testing.

**Spec:** `docs/superpowers/specs/2026-10-14-iphone-mcp-design.md` — read it before starting any task.

## Global Constraints

- Package root: `~/Documents/mnt/iphone-mcp` (git repo already initialised; spec committed).
- `swift-tools-version:6.1`, `platforms: [.macOS(.v15)]`, `swiftLanguageModes: [.v5]`.
- MCP SDK pinned: `.package(url: "https://github.com/modelcontextprotocol/swift-sdk.git", exact: "0.12.1")`, product `MCP`.
- Target app bundle id: `com.apple.ScreenContinuity`.
- Model coordinate space: pixels of the 1× screenshot, origin = phone screen top-left; bezel inset in window points `top 38, left 8, bottom 8, right 8` (measured in the spike: 2× capture content spans x 16…743, y 76…1657 of 760×1674).
- Error codes exactly: `MIRRORING_NOT_RUNNING`, `PHONE_NOT_CONNECTED`, `PERMISSION_SCREEN`, `PERMISSION_AX`, `ACTIVATION_TIMEOUT`, `TARGET_OCCLUDED`, `OUT_OF_BOUNDS`, `TEXT_NOT_FOUND`, `TEXT_AMBIGUOUS` (plus `INVALID_ARGUMENT` for malformed tool arguments).
- Takeover defaults: idle threshold 0.75 s, idle max wait 3 s, activation timeout 1 s, post-activation settle 250 ms (env override `IPHONE_MCP_SETTLE_MS`).
- Settle: sample every 100 ms until two consecutive frames differ by < 0.5 % of pixels (per-pixel RGB delta > 60), max 1.5 s.
- OCR: `VNRecognizeTextRequest`, `.accurate`, languages `zh-Hans, zh-Hant, en-US`, `usesLanguageCorrection = false`.
- Env: `IPHONE_MCP_READONLY=1` → only `screenshot`, `screenshot_text`, `status`; `IPHONE_MCP_LOG=<path>` → append tool name + argument *keys* only (never values, never images).
- In serve mode nothing but JSON-RPC may be written to stdout.
- Commit after every task; message ends with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.
- **Live-phone safety for executors:** any step that drives the real phone must only use harmless actions (Spotlight, typing into Spotlight, Home, scrolling Spotlight results). Never tap app icons or start a swipe on the home screen. Treat the phone as a real personal device.

## Review Focus

1. **User is moving the mouse/typing when an action arrives** → the action waits for ≤ 3 s of idleness and does not treat its *own* previous events as user activity. Pinned by `IdleGate` tests in Task 4.
2. **Phone locked, "iPhone in Use", or disconnected** (Mirroring shows native Mac UI instead of the stream) → every tool except `status` returns `PHONE_NOT_CONNECTED` and posts no input. Pinned by `SessionState` tests in Task 5.
3. **Non-ASCII text in `type_text`** (Chinese, emoji with surrogate pairs / skin-tone sequences, newlines) → each grapheme is sent intact; `\n` becomes Return. Pinned by `EventPlan.typeText` tests in Task 4.
4. **Malformed LLM arguments** (numbers as strings, NaN, negative/huge durations, unknown key names, missing fields) → `INVALID_ARGUMENT`/`OUT_OF_BOUNDS` with a readable message, never a crash or an out-of-range gesture. Pinned by `Args` tests in Task 8 and `Geometry` tests in Task 1.
5. **Window moved, resized or minimized between screenshot and action** → conversion uses the live frame; minimized window is restored before input. Pinned by the moved-window `Geometry` test in Task 1 and the minimized check in Task 10's selftest procedure.

---

## File Structure

```
Package.swift
Sources/IPhoneMCPCore/
  MirrorError.swift      error enum, codes, messages
  Geometry.swift         PhoneGeometry: 1× screenshot px ↔ global points (pure)
  ImageOps.swift         crop / resize / PNG / changedFraction (pure CG)
  Settle.swift           settle predicate (pure)
  OCR.swift              TextLine, Vision recognition, reading order
  TextMatcher.swift      tap_text matching (pure)
  EventPlan.swift        InputStep, KeyCode, Modifier, gesture/key builders (pure)
  IdleGate.swift         "is the user active" decision (pure)
  SessionState.swift     live vs blocked from AX nodes (pure)
  MirrorWindow.swift     process/window lookup, AX activation, hit-testing (system)
  Permissions.swift      TCC checks + responsible app name (system)
  Capturer.swift         ScreenCaptureKit capture → Screenshot (system)
  Takeover.swift         actor executing InputSteps with activate/restore (system)
  Args.swift             typed access to MCP tool arguments (pure)
  Log.swift              optional action log
  PhoneTools.swift       tool definitions + dispatch → CallTool.Result
Sources/iphone-mcp/
  main.swift             subcommands: serve (default) | status | call | selftest
  SelfTest.swift         on-device harmless selftest
Tests/IPhoneMCPCoreTests/
  TestImages.swift       helpers to synthesise CGImages
  GeometryTests.swift  ImageOpsTests.swift  OCRTests.swift  TextMatcherTests.swift
  EventPlanTests.swift IdleGateTests.swift  SessionStateTests.swift  ArgsTests.swift
  PhoneToolsTests.swift
scripts/smoke.sh         JSON-RPC initialize + tools/list against the binary
README.md
```

---

### Task 1: Package scaffold, MirrorError, Geometry

**Files:**
- Create: `Package.swift`, `Sources/IPhoneMCPCore/MirrorError.swift`, `Sources/IPhoneMCPCore/Geometry.swift`, `Sources/iphone-mcp/main.swift` (placeholder that prints usage), `Tests/IPhoneMCPCoreTests/GeometryTests.swift`, `.gitignore`

**Interfaces:**
- Produces:
  - `public enum MirrorError: Error, Equatable` with cases `mirroringNotRunning`, `phoneNotConnected(detail: String)`, `permissionScreen(app: String)`, `permissionAX(app: String)`, `activationTimeout(detail: String)`, `targetOccluded(owner: String)`, `outOfBounds(x: Double, y: Double, width: Double, height: Double)`, `textNotFound(String)`, `textAmbiguous(query: String, matches: [String])`, `invalidArgument(String)`; `var code: String`, `var message: String`.
  - `public struct Insets`, `public struct PhoneGeometry { init(windowFrame: CGRect, inset: Insets = .bezel); var screenRectInWindow: CGRect; var screenSize: CGSize; func toGlobal(x: Double, y: Double) throws -> CGPoint }`.

- [ ] **Step 1: Create the package skeleton**

`Package.swift`:
```swift
// swift-tools-version:6.1
import PackageDescription

let package = Package(
    name: "iphone-mcp",
    platforms: [.macOS(.v15)],
    dependencies: [
        .package(url: "https://github.com/modelcontextprotocol/swift-sdk.git", exact: "0.12.1"),
    ],
    targets: [
        .target(name: "IPhoneMCPCore", dependencies: [.product(name: "MCP", package: "swift-sdk")]),
        .executableTarget(name: "iphone-mcp", dependencies: ["IPhoneMCPCore", .product(name: "MCP", package: "swift-sdk")]),
        .testTarget(name: "IPhoneMCPCoreTests", dependencies: ["IPhoneMCPCore"]),
    ],
    swiftLanguageModes: [.v5]
)
```

`.gitignore`:
```
.build/
.swiftpm/
*.png
```

`Sources/iphone-mcp/main.swift`:
```swift
import IPhoneMCPCore
print("iphone-mcp: not implemented yet")
```

`Sources/IPhoneMCPCore/MirrorError.swift`:
```swift
import Foundation

public enum MirrorError: Error, Equatable {
    case mirroringNotRunning
    case phoneNotConnected(detail: String)
    case permissionScreen(app: String)
    case permissionAX(app: String)
    case activationTimeout(detail: String)
    case targetOccluded(owner: String)
    case outOfBounds(x: Double, y: Double, width: Double, height: Double)
    case textNotFound(String)
    case textAmbiguous(query: String, matches: [String])
    case invalidArgument(String)

    public var code: String {
        switch self {
        case .mirroringNotRunning: "MIRRORING_NOT_RUNNING"
        case .phoneNotConnected: "PHONE_NOT_CONNECTED"
        case .permissionScreen: "PERMISSION_SCREEN"
        case .permissionAX: "PERMISSION_AX"
        case .activationTimeout: "ACTIVATION_TIMEOUT"
        case .targetOccluded: "TARGET_OCCLUDED"
        case .outOfBounds: "OUT_OF_BOUNDS"
        case .textNotFound: "TEXT_NOT_FOUND"
        case .textAmbiguous: "TEXT_AMBIGUOUS"
        case .invalidArgument: "INVALID_ARGUMENT"
        }
    }

    public var message: String {
        switch self {
        case .mirroringNotRunning:
            "iPhone Mirroring is not running. Ask the user to open it and connect the phone."
        case .phoneNotConnected(let detail):
            "The phone stream is not live (\(detail)). Ask the user to unlock/reconnect the phone."
        case .permissionScreen(let app):
            "Screen Recording permission missing. Grant it to \(app) in System Settings > Privacy & Security > Screen & System Audio Recording, then restart \(app)."
        case .permissionAX(let app):
            "Accessibility permission missing. Grant it to \(app) in System Settings > Privacy & Security > Accessibility."
        case .activationTimeout(let detail):
            "Could not bring iPhone Mirroring to the front within 1 s (\(detail)). Nothing was sent."
        case .targetOccluded(let owner):
            "The point is covered by \(owner); nothing was clicked."
        case .outOfBounds(let x, let y, let w, let h):
            "Point (\(x), \(y)) is outside the phone screen (0..<\(Int(w)), 0..<\(Int(h)))."
        case .textNotFound(let q):
            "No on-screen text matches \"\(q)\"."
        case .textAmbiguous(let q, let matches):
            "\"\(q)\" matches \(matches.count) places; pass occurrence (1-based): " + matches.enumerated().map { "\($0.offset + 1)=\($0.element)" }.joined(separator: "; ")
        case .invalidArgument(let m):
            m
        }
    }
}
```

- [ ] **Step 2: Write the failing Geometry tests**

`Tests/IPhoneMCPCoreTests/GeometryTests.swift`:
```swift
import CoreGraphics
import Testing
@testable import IPhoneMCPCore

@Suite struct GeometryTests {
    let g = PhoneGeometry(windowFrame: CGRect(x: 509, y: 56, width: 380, height: 837))

    @Test func screenSizeExcludesBezel() {
        #expect(g.screenSize == CGSize(width: 364, height: 791))
        #expect(g.screenRectInWindow == CGRect(x: 8, y: 38, width: 364, height: 791))
    }

    @Test func originMapsToScreenTopLeft() throws {
        #expect(try g.toGlobal(x: 0, y: 0) == CGPoint(x: 517, y: 94))
        #expect(try g.toGlobal(x: 100, y: 200) == CGPoint(x: 617, y: 294))
    }

    @Test func movedWindowUsesNewFrame() throws {
        let moved = PhoneGeometry(windowFrame: CGRect(x: 438, y: 57, width: 380, height: 836))
        #expect(try moved.toGlobal(x: 100, y: 200) == CGPoint(x: 546, y: 295))
    }

    @Test(arguments: [(-1.0, 0.0), (0.0, -0.5), (364.0, 10.0), (10.0, 791.0), (Double.nan, 5.0), (5.0, .infinity)])
    func rejectsOutOfBounds(_ p: (Double, Double)) {
        #expect(throws: MirrorError.self) { try g.toGlobal(x: p.0, y: p.1) }
    }

    @Test func outOfBoundsErrorCarriesScreenSize() {
        #expect(throws: MirrorError.outOfBounds(x: 400, y: 1, width: 364, height: 791)) { try g.toGlobal(x: 400, y: 1) }
    }
}
```

- [ ] **Step 3: Run tests to verify they fail**

Run: `cd ~/Documents/mnt/iphone-mcp && swift test --filter GeometryTests 2>&1 | tail -5`
Expected: compile failure — `cannot find 'PhoneGeometry' in scope`.

- [ ] **Step 4: Implement Geometry**

`Sources/IPhoneMCPCore/Geometry.swift`:
```swift
import CoreGraphics

public struct Insets: Equatable, Sendable {
    public var top, left, bottom, right: Double
    public init(top: Double, left: Double, bottom: Double, right: Double) {
        self.top = top; self.left = left; self.bottom = bottom; self.right = right
    }
}

/// Maps the model's coordinate space (1× screenshot pixels, origin at the phone
/// screen's top-left) to global screen points (CGWindow space, origin top-left).
public struct PhoneGeometry: Equatable, Sendable {
    /// Window chrome around the phone screen, in points (measured on macOS 27).
    public static let bezel = Insets(top: 38, left: 8, bottom: 8, right: 8)

    public let windowFrame: CGRect
    public let inset: Insets

    public init(windowFrame: CGRect, inset: Insets = PhoneGeometry.bezel) {
        self.windowFrame = windowFrame
        self.inset = inset
    }

    public var screenRectInWindow: CGRect {
        CGRect(x: inset.left, y: inset.top,
               width: windowFrame.width - inset.left - inset.right,
               height: windowFrame.height - inset.top - inset.bottom)
    }

    public var screenSize: CGSize { screenRectInWindow.size }

    public func toGlobal(x: Double, y: Double) throws -> CGPoint {
        let s = screenSize
        guard x.isFinite, y.isFinite, x >= 0, y >= 0, x < s.width, y < s.height else {
            throw MirrorError.outOfBounds(x: x, y: y, width: s.width, height: s.height)
        }
        return CGPoint(x: windowFrame.minX + inset.left + x, y: windowFrame.minY + inset.top + y)
    }
}
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `swift test --filter GeometryTests 2>&1 | tail -3`
Expected: `Test run with 10 tests … passed` (5 functions, 6 parameterised cases counted individually is fine — all pass).

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "Scaffold package with MirrorError and PhoneGeometry

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 2: ImageOps and Settle

**Files:**
- Create: `Sources/IPhoneMCPCore/ImageOps.swift`, `Sources/IPhoneMCPCore/Settle.swift`, `Tests/IPhoneMCPCoreTests/TestImages.swift`, `Tests/IPhoneMCPCoreTests/ImageOpsTests.swift`

**Interfaces:**
- Consumes: nothing.
- Produces:
  - `public enum ImageOps { static func crop(_: CGImage, windowPointRect: CGRect, pixelsPerPoint: Double) -> CGImage?; static func resize(_: CGImage, width: Int, height: Int) -> CGImage?; static func png(_: CGImage) -> Data?; static func changedFraction(_: CGImage, _: CGImage, threshold: Int = 60) -> Double; static func rgba(_: CGImage) -> [UInt8] }`
  - `public enum Settle { static let maxChangedFraction = 0.005; static func isSettled(_: CGImage, _: CGImage) -> Bool }`
  - Test helper `TestImages.make(width:height:draw:)`, `TestImages.solid(width:height:r:g:b:)`.

- [ ] **Step 1: Write test helpers and failing tests**

`Tests/IPhoneMCPCoreTests/TestImages.swift`:
```swift
import CoreGraphics

enum TestImages {
    /// Draw with a CGContext whose origin is the TOP-left (flipped), like image pixel coordinates.
    static func make(width: Int, height: Int, draw: (CGContext) -> Void) -> CGImage {
        let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.translateBy(x: 0, y: CGFloat(height))
        ctx.scaleBy(x: 1, y: -1)
        draw(ctx)
        return ctx.makeImage()!
    }

    static func solid(width: Int, height: Int, r: CGFloat, g: CGFloat, b: CGFloat) -> CGImage {
        make(width: width, height: height) { ctx in
            ctx.setFillColor(red: r, green: g, blue: b, alpha: 1)
            ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        }
    }
}
```

`Tests/IPhoneMCPCoreTests/ImageOpsTests.swift`:
```swift
import CoreGraphics
import Testing
@testable import IPhoneMCPCore

@Suite struct ImageOpsTests {
    @Test func cropUsesTopLeftOriginAndScale() {
        // 100×200 white image with a red 10×10 square in the top-left corner.
        let img = TestImages.make(width: 100, height: 200) { ctx in
            ctx.setFillColor(red: 1, green: 1, blue: 1, alpha: 1); ctx.fill(CGRect(x: 0, y: 0, width: 100, height: 200))
            ctx.setFillColor(red: 1, green: 0, blue: 0, alpha: 1); ctx.fill(CGRect(x: 0, y: 0, width: 10, height: 10))
        }
        let c = ImageOps.crop(img, windowPointRect: CGRect(x: 0, y: 0, width: 5, height: 5), pixelsPerPoint: 2)!
        #expect(c.width == 10 && c.height == 10)
        let px = ImageOps.rgba(c)
        #expect(px[0] > 200 && px[1] < 50 && px[2] < 50)              // first pixel red
        #expect(px[px.count - 4] > 200 && px[px.count - 3] < 50)      // last pixel red
    }

    @Test func resizeProducesRequestedSize() {
        let r = ImageOps.resize(TestImages.solid(width: 728, height: 1582, r: 0, g: 0, b: 1), width: 364, height: 791)!
        #expect(r.width == 364 && r.height == 791)
    }

    @Test func pngHasSignature() {
        let d = ImageOps.png(TestImages.solid(width: 4, height: 4, r: 0, g: 1, b: 0))!
        #expect(Array(d.prefix(4)) == [0x89, 0x50, 0x4E, 0x47])
    }

    @Test func changedFractionIdenticalIsZero() {
        let a = TestImages.solid(width: 20, height: 20, r: 0.5, g: 0.5, b: 0.5)
        #expect(ImageOps.changedFraction(a, a) == 0)
    }

    @Test func changedFractionHalf() {
        let a = TestImages.solid(width: 20, height: 20, r: 0, g: 0, b: 0)
        let b = TestImages.make(width: 20, height: 20) { ctx in
            ctx.setFillColor(red: 0, green: 0, blue: 0, alpha: 1); ctx.fill(CGRect(x: 0, y: 0, width: 20, height: 20))
            ctx.setFillColor(red: 1, green: 1, blue: 1, alpha: 1); ctx.fill(CGRect(x: 0, y: 0, width: 20, height: 10))
        }
        #expect(abs(ImageOps.changedFraction(a, b) - 0.5) < 0.001)
    }

    @Test func smallDeltaBelowThresholdIgnored() {
        let a = TestImages.solid(width: 10, height: 10, r: 0.50, g: 0.50, b: 0.50)
        let b = TestImages.solid(width: 10, height: 10, r: 0.52, g: 0.52, b: 0.52) // ~5 per channel → 15 < 60
        #expect(ImageOps.changedFraction(a, b) == 0)
    }

    @Test func sizeMismatchCountsAsFullyChanged() {
        #expect(ImageOps.changedFraction(TestImages.solid(width: 10, height: 10, r: 0, g: 0, b: 0),
                                         TestImages.solid(width: 10, height: 11, r: 0, g: 0, b: 0)) == 1)
    }

    @Test func settleThreshold() {
        let a = TestImages.solid(width: 100, height: 100, r: 0, g: 0, b: 0)
        let tiny = TestImages.make(width: 100, height: 100) { ctx in   // 40 px changed = 0.4 %
            ctx.setFillColor(red: 0, green: 0, blue: 0, alpha: 1); ctx.fill(CGRect(x: 0, y: 0, width: 100, height: 100))
            ctx.setFillColor(red: 1, green: 1, blue: 1, alpha: 1); ctx.fill(CGRect(x: 0, y: 0, width: 40, height: 1))
        }
        let big = TestImages.make(width: 100, height: 100) { ctx in    // 100 px changed = 1 %
            ctx.setFillColor(red: 0, green: 0, blue: 0, alpha: 1); ctx.fill(CGRect(x: 0, y: 0, width: 100, height: 100))
            ctx.setFillColor(red: 1, green: 1, blue: 1, alpha: 1); ctx.fill(CGRect(x: 0, y: 0, width: 100, height: 1))
        }
        #expect(Settle.isSettled(a, tiny))
        #expect(!Settle.isSettled(a, big))
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter ImageOpsTests 2>&1 | tail -5`
Expected: compile failure — `cannot find 'ImageOps' in scope`.

- [ ] **Step 3: Implement ImageOps and Settle**

`Sources/IPhoneMCPCore/ImageOps.swift`:
```swift
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

public enum ImageOps {
    /// Crop a window capture to a rect given in window points.
    public static func crop(_ image: CGImage, windowPointRect r: CGRect, pixelsPerPoint s: Double) -> CGImage? {
        let px = CGRect(x: (r.minX * s).rounded(), y: (r.minY * s).rounded(),
                        width: (r.width * s).rounded(), height: (r.height * s).rounded())
            .intersection(CGRect(x: 0, y: 0, width: image.width, height: image.height))
        guard !px.isEmpty else { return nil }
        return image.cropping(to: px)
    }

    public static func resize(_ image: CGImage, width: Int, height: Int) -> CGImage? {
        guard width > 0, height > 0,
              let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.interpolationQuality = .high
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return ctx.makeImage()
    }

    public static func png(_ image: CGImage) -> Data? {
        let data = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(dest, image, nil)
        return CGImageDestinationFinalize(dest) ? data as Data : nil
    }

    /// RGBA8 pixels, row 0 = top of the image.
    public static func rgba(_ image: CGImage) -> [UInt8] {
        let w = image.width, h = image.height
        var buf = [UInt8](repeating: 0, count: w * h * 4)
        buf.withUnsafeMutableBytes { raw in
            let ctx = CGContext(data: raw.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        }
        return buf
    }

    /// Fraction of pixels whose summed |ΔR|+|ΔG|+|ΔB| exceeds `threshold`. Size mismatch → 1.
    public static func changedFraction(_ a: CGImage, _ b: CGImage, threshold: Int = 60) -> Double {
        guard a.width == b.width, a.height == b.height, a.width > 0, a.height > 0 else { return 1 }
        let pa = rgba(a), pb = rgba(b)
        var changed = 0
        for i in stride(from: 0, to: pa.count, by: 4) {
            let d = abs(Int(pa[i]) - Int(pb[i])) + abs(Int(pa[i + 1]) - Int(pb[i + 1])) + abs(Int(pa[i + 2]) - Int(pb[i + 2]))
            if d > threshold { changed += 1 }
        }
        return Double(changed) / Double(a.width * a.height)
    }
}
```

`Sources/IPhoneMCPCore/Settle.swift`:
```swift
import CoreGraphics

public enum Settle {
    public static let maxChangedFraction = 0.005
    public static func isSettled(_ a: CGImage, _ b: CGImage) -> Bool {
        ImageOps.changedFraction(a, b) < maxChangedFraction
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter ImageOpsTests 2>&1 | tail -3`
Expected: all 8 tests pass.

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "Add ImageOps (crop/resize/png/diff) and Settle predicate

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 3: OCR and TextMatcher

**Files:**
- Create: `Sources/IPhoneMCPCore/OCR.swift`, `Sources/IPhoneMCPCore/TextMatcher.swift`, `Tests/IPhoneMCPCoreTests/OCRTests.swift`, `Tests/IPhoneMCPCoreTests/TextMatcherTests.swift`

**Interfaces:**
- Consumes: `MirrorError` (Task 1), `TestImages` (Task 2).
- Produces:
  - `public struct TextLine: Codable, Equatable, Sendable { text: String; x, y, w, h: Int; confidence: Double; var centerX: Int; var centerY: Int }`
  - `public enum OCR { static func recognize(_: CGImage, outputScale: Double) throws -> [TextLine]; static func readingOrder(_: [TextLine]) -> [TextLine] }`
  - `public enum TextMatcher { static func find(_ query: String, in: [TextLine], occurrence: Int?) throws -> TextLine }`

- [ ] **Step 1: Write failing tests**

`Tests/IPhoneMCPCoreTests/TextMatcherTests.swift`:
```swift
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
```

`Tests/IPhoneMCPCoreTests/OCRTests.swift`:
```swift
import AppKit
import CoreText
import Testing
@testable import IPhoneMCPCore

@Suite struct OCRTests {
    @Test func readingOrderGroupsRowsLeftToRight() {
        let a = line("A", 200, 10), b = line("B", 10, 14), c = line("C", 5, 100)
        #expect(OCR.readingOrder([c, a, b]).map(\.text) == ["B", "A", "C"])
    }

    @Test func recognizesEnglishAndChineseWithScaledBoxes() throws {
        // 800×400 white image (a "2×" capture), text baseline 100 px from the top.
        let img = TestImages.make(width: 800, height: 400) { ctx in
            ctx.setFillColor(red: 1, green: 1, blue: 1, alpha: 1); ctx.fill(CGRect(x: 0, y: 0, width: 800, height: 400))
            // Undo the helper's flip for text drawing so glyphs are upright.
            ctx.saveGState(); ctx.translateBy(x: 0, y: 400); ctx.scaleBy(x: 1, y: -1)
            let attr = NSAttributedString(string: "Settings   设置", attributes: [
                .font: NSFont.systemFont(ofSize: 48), .foregroundColor: NSColor.black])
            ctx.textPosition = CGPoint(x: 40, y: 300)
            CTLineDraw(CTLineCreateWithAttributedString(attr), ctx)
            ctx.restoreGState()
        }
        let lines = try OCR.recognize(img, outputScale: 2)
        let all = lines.map(\.text).joined(separator: " ")
        #expect(all.contains("Settings"))
        #expect(all.contains("设置"))
        let first = try #require(lines.first)
        #expect((10...30).contains(first.x))   // 40 px / 2 ≈ 20 pt
        #expect((15...50).contains(first.y))   // top of 48 px glyphs at ~55 px / 2
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter 'TextMatcherTests|OCRTests' 2>&1 | tail -5`
Expected: compile failure — `cannot find type 'TextLine'`.

- [ ] **Step 3: Implement OCR and TextMatcher**

`Sources/IPhoneMCPCore/OCR.swift`:
```swift
import CoreGraphics
import Vision

public struct TextLine: Codable, Equatable, Sendable {
    public var text: String
    public var x, y, w, h: Int
    public var confidence: Double
    public init(text: String, x: Int, y: Int, w: Int, h: Int, confidence: Double) {
        self.text = text; self.x = x; self.y = y; self.w = w; self.h = h; self.confidence = confidence
    }
    public var centerX: Int { x + w / 2 }
    public var centerY: Int { y + h / 2 }
}

public enum OCR {
    /// Recognise text in `image`; boxes are returned in image pixels divided by `outputScale`
    /// (pass 2 for a 2× capture to get 1× model coordinates).
    public static func recognize(_ image: CGImage, outputScale: Double) throws -> [TextLine] {
        let req = VNRecognizeTextRequest()
        req.recognitionLevel = .accurate
        req.usesLanguageCorrection = false
        req.recognitionLanguages = ["zh-Hans", "zh-Hant", "en-US"]
        try VNImageRequestHandler(cgImage: image).perform([req])
        let W = Double(image.width), H = Double(image.height)
        let lines: [TextLine] = (req.results ?? []).compactMap { obs in
            guard let c = obs.topCandidates(1).first else { return nil }
            let bb = obs.boundingBox   // normalised, origin bottom-left
            return TextLine(text: c.string,
                            x: Int((bb.minX * W / outputScale).rounded()),
                            y: Int(((1 - bb.maxY) * H / outputScale).rounded()),
                            w: Int((bb.width * W / outputScale).rounded()),
                            h: Int((bb.height * H / outputScale).rounded()),
                            confidence: (Double(c.confidence) * 100).rounded() / 100)
        }
        return readingOrder(lines)
    }

    /// Top-to-bottom rows (lines whose vertical centres are within half a line height), each left-to-right.
    public static func readingOrder(_ lines: [TextLine]) -> [TextLine] {
        let byY = lines.sorted { ($0.centerY, $0.x) < ($1.centerY, $1.x) }
        var rows: [[TextLine]] = []
        for l in byY {
            if let first = rows.last?.first, abs(l.centerY - first.centerY) <= max(first.h / 2, 1) {
                rows[rows.count - 1].append(l)
            } else {
                rows.append([l])
            }
        }
        return rows.flatMap { $0.sorted { $0.x < $1.x } }
    }
}
```

`Sources/IPhoneMCPCore/TextMatcher.swift`:
```swift
import Foundation

public enum TextMatcher {
    /// Exact (trimmed) match first, else case-insensitive substring. Multiple matches need `occurrence` (1-based).
    public static func find(_ query: String, in lines: [TextLine], occurrence: Int?) throws -> TextLine {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { throw MirrorError.invalidArgument("text must not be empty") }
        var matches = lines.filter { $0.text.trimmingCharacters(in: .whitespacesAndNewlines) == q }
        if matches.isEmpty {
            matches = lines.filter { $0.text.range(of: q, options: [.caseInsensitive]) != nil }
        }
        guard !matches.isEmpty else { throw MirrorError.textNotFound(q) }
        if let n = occurrence {
            guard n >= 1, n <= matches.count else {
                throw MirrorError.invalidArgument("occurrence \(n) out of range 1...\(matches.count)")
            }
            return matches[n - 1]
        }
        guard matches.count == 1 else {
            throw MirrorError.textAmbiguous(query: q, matches: matches.map { "\($0.text) @ (\($0.centerX),\($0.centerY))" })
        }
        return matches[0]
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter 'TextMatcherTests|OCRTests' 2>&1 | tail -3`
Expected: all pass. If `recognizesEnglishAndChineseWithScaledBoxes` fails only on the box ranges, print `lines` and correct the expected ranges from the actual geometry (the text assertions must still pass unchanged).

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "Add Vision OCR with reading order and tap_text matcher

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 4: EventPlan and IdleGate (pure input planning)

**Files:**
- Create: `Sources/IPhoneMCPCore/EventPlan.swift`, `Sources/IPhoneMCPCore/IdleGate.swift`, `Tests/IPhoneMCPCoreTests/EventPlanTests.swift`, `Tests/IPhoneMCPCoreTests/IdleGateTests.swift`

**Interfaces:**
- Produces:
  - `public enum InputStep: Equatable, Sendable { case move(CGPoint), down(CGPoint), drag(CGPoint), up(CGPoint), key(code: UInt16, down: Bool, flags: UInt64), text([UInt16]), sleep(ms: Int) }`
  - `public enum Modifier { case command, shift }` with `keyCode: UInt16`, `flag: UInt64`
  - `public enum KeyCode { static let named: [String: UInt16]; static let one: UInt16 = 18, two = 19, three = 20, returnKey = 36 }`
  - `public enum EventPlan { static func tap(_:from:) ; longPress(_:ms:from:); swipe(_:_:durationMs:from:); drag(_:_:holdMs:durationMs:from:); keyCombo(_:_:); typeText(_:) }` — all return `[InputStep]`, points are global.
  - `public enum IdleGate { static func userIsActive(lastInputAgo: Double, ourLastPostAgo: Double?, threshold: Double) -> Bool }`

- [ ] **Step 1: Write failing tests**

`Tests/IPhoneMCPCoreTests/EventPlanTests.swift`:
```swift
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
}
```

`Tests/IPhoneMCPCoreTests/IdleGateTests.swift`:
```swift
import Testing
@testable import IPhoneMCPCore

@Suite struct IdleGateTests {
    @Test func idleWhenNoRecentInput() { #expect(!IdleGate.userIsActive(lastInputAgo: 2, ourLastPostAgo: nil, threshold: 0.75)) }
    @Test func activeWhenRecentInputAndWeNeverPosted() { #expect(IdleGate.userIsActive(lastInputAgo: 0.1, ourLastPostAgo: nil, threshold: 0.75)) }
    @Test func ourOwnLastEventIsNotUserActivity() { #expect(!IdleGate.userIsActive(lastInputAgo: 0.30, ourLastPostAgo: 0.32, threshold: 0.75)) }
    @Test func userInputAfterOursIsActivity() { #expect(IdleGate.userIsActive(lastInputAgo: 0.1, ourLastPostAgo: 0.5, threshold: 0.75)) }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter 'EventPlanTests|IdleGateTests' 2>&1 | tail -5`
Expected: compile failure — `cannot find 'EventPlan' in scope`.

- [ ] **Step 3: Implement**

`Sources/IPhoneMCPCore/EventPlan.swift`:
```swift
import CoreGraphics

public enum InputStep: Equatable, Sendable {
    case move(CGPoint)
    case down(CGPoint)
    case drag(CGPoint)
    case up(CGPoint)
    case key(code: UInt16, down: Bool, flags: UInt64)
    case text([UInt16])          // one grapheme, sent as one key down/up with a Unicode string
    case sleep(ms: Int)
}

public enum Modifier: Sendable {
    case command, shift
    public var keyCode: UInt16 { self == .command ? 55 : 56 }
    public var flag: UInt64 { self == .command ? CGEventFlags.maskCommand.rawValue : CGEventFlags.maskShift.rawValue }
}

public enum KeyCode {
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
```

`Sources/IPhoneMCPCore/IdleGate.swift`:
```swift
public enum IdleGate {
    /// - lastInputAgo: seconds since the last HID event of any source (includes our own posts).
    /// - ourLastPostAgo: seconds since this process last finished posting, nil if never.
    public static func userIsActive(lastInputAgo: Double, ourLastPostAgo: Double?, threshold: Double) -> Bool {
        guard lastInputAgo < threshold else { return false }
        if let ours = ourLastPostAgo, lastInputAgo >= ours - 0.05 { return false }   // the latest input was ours
        return true
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter 'EventPlanTests|IdleGateTests' 2>&1 | tail -3`
Expected: all pass.

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "Add pure input planning (gestures, key combos, text) and IdleGate

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 5: SessionState, MirrorWindow, Permissions, `status` subcommand

**Files:**
- Create: `Sources/IPhoneMCPCore/SessionState.swift`, `Sources/IPhoneMCPCore/MirrorWindow.swift`, `Sources/IPhoneMCPCore/Permissions.swift`, `Tests/IPhoneMCPCoreTests/SessionStateTests.swift`
- Modify: `Sources/iphone-mcp/main.swift` (replace placeholder)

**Interfaces:**
- Consumes: `MirrorError`, `PhoneGeometry`.
- Produces:
  - `public enum SessionState: Equatable { case ready, blocked([String]); static func from(nodes: [(role: String, text: String)]) -> SessionState }`
  - `public struct MirrorTarget { pid: pid_t; windowID: CGWindowID; frame: CGRect; axWindow: AXUIElement?; minimized: Bool; var geometry: PhoneGeometry }`
  - `public enum MirrorWindow { static let bundleID; static func runningPID() -> pid_t?; static func locate() throws -> MirrorTarget; static func session(_: MirrorTarget) -> SessionState; static func requireLive(_: MirrorTarget) throws; static func frontmostOwnerPID() -> pid_t?; static func topmostOwner(at: CGPoint) -> (pid: pid_t, name: String)?; static func isFrontmost(_: MirrorTarget) -> Bool; static func setFrontmost(_: pid_t); static func raise(_: MirrorTarget); static func unminimize(_: MirrorTarget) }`
  - `public enum Permissions { static var screenRecording: Bool; static var accessibility: Bool; static func responsibleAppName() -> String; static func require() throws }`
  - `public enum Status { static func json() -> String }` (in MirrorWindow.swift)

- [ ] **Step 1: Write failing SessionState tests**

`Tests/IPhoneMCPCoreTests/SessionStateTests.swift`:
```swift
import Testing
@testable import IPhoneMCPCore

@Suite struct SessionStateTests {
    @Test func noNativeUIMeansLiveStream() { #expect(SessionState.from(nodes: []) == .ready) }

    @Test func nativeUIMeansBlockedWithTexts() {
        #expect(SessionState.from(nodes: [("AXStaticText", "iPhone in Use"), ("AXButton", ""), ("AXStaticText", "  ")])
                == .blocked(["iPhone in Use"]))
    }

    @Test func blockedEvenWithoutReadableText() {
        #expect(SessionState.from(nodes: [("AXButton", "")]) == .blocked([]))
    }
}
```

- [ ] **Step 2: Run to verify failure**

Run: `swift test --filter SessionStateTests 2>&1 | tail -5`
Expected: compile failure — `cannot find 'SessionState'`.

- [ ] **Step 3: Implement SessionState, MirrorWindow, Permissions**

`Sources/IPhoneMCPCore/SessionState.swift`:
```swift
import Foundation

/// A live stream exposes no AX elements inside the window; the lock / "iPhone in Use" /
/// connect screens are native Mac views and do (finding from phone-harness, holds on any locale).
public enum SessionState: Equatable, Sendable {
    case ready
    case blocked([String])

    public static func from(nodes: [(role: String, text: String)]) -> SessionState {
        guard !nodes.isEmpty else { return .ready }
        return .blocked(nodes.map { $0.text.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty })
    }
}
```

`Sources/IPhoneMCPCore/MirrorWindow.swift`:
```swift
import AppKit
import ApplicationServices

public struct MirrorTarget {
    public let pid: pid_t
    public let windowID: CGWindowID
    public let frame: CGRect          // global points, top-left origin
    public let axWindow: AXUIElement?
    public let minimized: Bool
    public var geometry: PhoneGeometry { PhoneGeometry(windowFrame: frame) }
}

public enum MirrorWindow {
    public static let bundleID = "com.apple.ScreenContinuity"

    public static func runningPID() -> pid_t? {
        NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first?.processIdentifier
    }

    static func windowList(onScreenOnly: Bool) -> [[String: Any]] {
        let opts: CGWindowListOption = onScreenOnly ? [.optionOnScreenOnly, .excludeDesktopElements] : [.optionAll]
        return (CGWindowListCopyWindowInfo(opts, kCGNullWindowID) as? [[String: Any]]) ?? []
    }

    static func bounds(_ w: [String: Any]) -> CGRect {
        guard let d = w[kCGWindowBounds as String] else { return .zero }
        return CGRect(dictionaryRepresentation: d as! CFDictionary) ?? .zero
    }
    static func ownerPID(_ w: [String: Any]) -> pid_t? { (w[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value }
    static func layer(_ w: [String: Any]) -> Int { (w[kCGWindowLayer as String] as? NSNumber)?.intValue ?? -1 }

    static func axCopy(_ el: AXUIElement, _ attr: String) -> CFTypeRef? {
        var v: CFTypeRef?
        return AXUIElementCopyAttributeValue(el, attr as CFString, &v) == .success ? v : nil
    }
    static func axFrame(_ el: AXUIElement) -> CGRect? {
        guard let p = axCopy(el, kAXPositionAttribute), let s = axCopy(el, kAXSizeAttribute) else { return nil }
        var pt = CGPoint.zero, sz = CGSize.zero
        AXValueGetValue(p as! AXValue, .cgPoint, &pt); AXValueGetValue(s as! AXValue, .cgSize, &sz)
        return CGRect(origin: pt, size: sz)
    }

    public static func locate() throws -> MirrorTarget {
        guard let pid = runningPID() else { throw MirrorError.mirroringNotRunning }
        let appName = NSRunningApplication(processIdentifier: pid)?.localizedName ?? "iPhone Mirroring"
        let candidates = windowList(onScreenOnly: false).filter {
            ownerPID($0) == pid && layer($0) == 0 && bounds($0).height > 300 && bounds($0).width > 200
        }
        let titled = candidates.first { ($0[kCGWindowName as String] as? String) == appName }
        guard let w = titled ?? candidates.max(by: { bounds($0).width * bounds($0).height < bounds($1).width * bounds($1).height }),
              let id = (w[kCGWindowNumber as String] as? NSNumber)?.uint32Value else {
            throw MirrorError.phoneNotConnected(detail: "iPhone Mirroring has no phone window")
        }
        let frame = bounds(w)
        let axWins = (axCopy(AXUIElementCreateApplication(pid), kAXWindowsAttribute) as? [AXUIElement]) ?? []
        let ax = axWins.first { axFrame($0)?.size == frame.size } ?? axWins.first
        let minimized = ax.flatMap { axCopy($0, kAXMinimizedAttribute) as? Bool } ?? false
        return MirrorTarget(pid: pid, windowID: id, frame: frame, axWindow: ax, minimized: minimized)
    }

    static let contentRoles: Set<String> = ["AXStaticText", "AXButton", "AXTextField", "AXSecureTextField", "AXImage"]

    public static func session(_ t: MirrorTarget) -> SessionState {
        guard let root = t.axWindow else { return .ready }
        var nodes: [(role: String, text: String)] = []
        var queue: [(AXUIElement, Int)] = [(root, 0)]
        while !queue.isEmpty {
            let (el, depth) = queue.removeFirst()
            if depth > 0, let role = axCopy(el, kAXRoleAttribute) as? String, contentRoles.contains(role) {
                let text = [kAXTitleAttribute, kAXValueAttribute, kAXDescriptionAttribute]
                    .compactMap { axCopy(el, $0) as? String }.first { !$0.isEmpty } ?? ""
                nodes.append((role, text))
            }
            if depth < 8, let kids = axCopy(el, kAXChildrenAttribute) as? [AXUIElement] {
                queue += kids.map { ($0, depth + 1) }
            }
        }
        return SessionState.from(nodes: nodes)
    }

    public static func requireLive(_ t: MirrorTarget) throws {
        if case .blocked(let texts) = session(t) {
            throw MirrorError.phoneNotConnected(detail: texts.isEmpty
                ? "the window shows a native screen instead of the phone"
                : texts.joined(separator: " / "))
        }
    }

    /// Owner of the frontmost normal-layer window. NSWorkspace.frontmostApplication is stale
    /// in a process without a run loop, so never use it here.
    public static func frontmostOwnerPID() -> pid_t? {
        windowList(onScreenOnly: true).first { layer($0) == 0 }.flatMap(ownerPID)
    }

    public static func topmostOwner(at p: CGPoint) -> (pid: pid_t, name: String)? {
        guard let w = windowList(onScreenOnly: true).first(where: { layer($0) == 0 && bounds($0).contains(p) }),
              let pid = ownerPID(w) else { return nil }
        return (pid, w[kCGWindowOwnerName as String] as? String ?? "pid \(pid)")
    }

    /// Both signals must agree: AX says frontmost AND the top window belongs to Mirroring.
    public static func isFrontmost(_ t: MirrorTarget) -> Bool {
        (axCopy(AXUIElementCreateApplication(t.pid), kAXFrontmostAttribute) as? Bool) == true
            && frontmostOwnerPID() == t.pid
    }

    public static func setFrontmost(_ pid: pid_t) {
        AXUIElementSetAttributeValue(AXUIElementCreateApplication(pid), kAXFrontmostAttribute as CFString, kCFBooleanTrue)
    }

    public static func raise(_ t: MirrorTarget) {
        if let w = t.axWindow { AXUIElementPerformAction(w, kAXRaiseAction as CFString) }
    }

    public static func unminimize(_ t: MirrorTarget) {
        if let w = t.axWindow { AXUIElementSetAttributeValue(w, kAXMinimizedAttribute as CFString, kCFBooleanFalse) }
    }
}

public enum Status {
    public static func json() -> String {
        var d: [String: Any] = [
            "permissions": ["screen_recording": Permissions.screenRecording, "accessibility": Permissions.accessibility],
            "responsible_app": Permissions.responsibleAppName(),
        ]
        do {
            let t = try MirrorWindow.locate()
            d["running"] = true
            d["window_frame"] = ["x": t.frame.minX, "y": t.frame.minY, "w": t.frame.width, "h": t.frame.height]
            d["minimized"] = t.minimized
            d["screen_size"] = ["w": t.geometry.screenSize.width, "h": t.geometry.screenSize.height]
            switch MirrorWindow.session(t) {
            case .ready: d["session"] = "ready"
            case .blocked(let texts): d["session"] = "blocked"; d["session_text"] = texts
            }
        } catch let e as MirrorError {
            d["running"] = e != .mirroringNotRunning
            d["session"] = e.code
        } catch {
            d["session"] = "\(error)"
        }
        let data = try! JSONSerialization.data(withJSONObject: d, options: [.sortedKeys])
        return String(data: data, encoding: .utf8)!
    }
}
```

`Sources/IPhoneMCPCore/Permissions.swift`:
```swift
import AppKit
import ApplicationServices

public enum Permissions {
    public static var screenRecording: Bool { CGPreflightScreenCaptureAccess() }
    public static var accessibility: Bool { AXIsProcessTrusted() }

    static func parentPID(_ pid: pid_t) -> pid_t? {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        guard sysctl(&mib, 4, &info, &size, nil, 0) == 0, size > 0 else { return nil }
        let p = info.kp_eproc.e_ppid
        return p > 1 ? p : nil
    }

    /// TCC attributes our requests to the nearest ancestor that is an .app (Claude, Terminal, …).
    public static func responsibleAppName() -> String {
        var pid: pid_t? = getpid()
        for _ in 0..<12 {
            guard let p = pid else { break }
            if let app = NSRunningApplication(processIdentifier: p), app.bundleURL?.pathExtension == "app" {
                return app.localizedName ?? app.bundleURL!.deletingPathExtension().lastPathComponent
            }
            pid = parentPID(p)
        }
        return "the app that launched iphone-mcp (e.g. Claude or Terminal)"
    }

    public static func require() throws {
        guard accessibility else { throw MirrorError.permissionAX(app: responsibleAppName()) }
        guard screenRecording else { throw MirrorError.permissionScreen(app: responsibleAppName()) }
    }
}
```

`Sources/iphone-mcp/main.swift`:
```swift
import AppKit
import IPhoneMCPCore

_ = NSApplication.shared   // required: initialises the window-server connection (CGS) for capture

let argv = Array(CommandLine.arguments.dropFirst())
switch argv.first {
case "status":
    print(Status.json())
default:
    FileHandle.standardError.write("usage: iphone-mcp [serve|status]\n".data(using: .utf8)!)
    exit(2)
}
```

- [ ] **Step 4: Run unit tests**

Run: `swift test --filter SessionStateTests 2>&1 | tail -3`
Expected: 3 tests pass.

- [ ] **Step 5: Verify against the live Mirroring window**

Run: `swift build -c release 2>&1 | tail -2 && .build/release/iphone-mcp status`
Expected (phone connected, values vary): JSON containing `"running":true`, `"session":"ready"`, `"screen_size":{"h":791,"w":364}` (or h 790), both permissions `true`, `"responsible_app"` naming Claude or the terminal. If `session` is `blocked` while the phone visibly streams, print the AX nodes found (temporary `print`) and report — do not loosen `SessionState` without user input.

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "Add Mirroring window discovery, session detection, permissions and status command

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 6: Capturer

**Files:**
- Create: `Sources/IPhoneMCPCore/Capturer.swift`
- Modify: `Sources/iphone-mcp/main.swift` (add `shot` case)

**Interfaces:**
- Consumes: `MirrorTarget`, `PhoneGeometry`, `ImageOps`, `Permissions`, `MirrorError`.
- Produces:
  - `public struct Screenshot { full: CGImage /* 2× phone screen */; model: CGImage /* 1× */; geometry: PhoneGeometry; frameID: Int; var pixelsPerPoint: Double }`
  - `public actor Capturer { init(); func capture(_: MirrorTarget) async throws -> Screenshot }`

- [ ] **Step 1: Implement Capturer**

`Sources/IPhoneMCPCore/Capturer.swift`:
```swift
import CoreGraphics
import ScreenCaptureKit

public struct Screenshot {
    public let full: CGImage       // phone screen at capture resolution (2×)
    public let model: CGImage      // 1× — the model's coordinate space
    public let geometry: PhoneGeometry
    public let frameID: Int
    public var pixelsPerPoint: Double { Double(full.width) / Double(model.width) }
}

public actor Capturer {
    private var counter = 0
    public init() {}

    public func capture(_ t: MirrorTarget) async throws -> Screenshot {
        let content: SCShareableContent
        do {
            content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
        } catch {
            throw MirrorError.permissionScreen(app: Permissions.responsibleAppName())
        }
        guard let w = content.windows.first(where: { $0.windowID == t.windowID }) else {
            throw MirrorError.phoneNotConnected(detail: "phone window is not capturable")
        }
        let cfg = SCStreamConfiguration()
        cfg.width = Int(t.frame.width * 2)
        cfg.height = Int(t.frame.height * 2)
        cfg.showsCursor = false
        let img = try await SCScreenshotManager.captureImage(
            contentFilter: SCContentFilter(desktopIndependentWindow: w), configuration: cfg)
        let g = t.geometry
        let s = Double(img.width) / Double(t.frame.width)
        guard let full = ImageOps.crop(img, windowPointRect: g.screenRectInWindow, pixelsPerPoint: s),
              let model = ImageOps.resize(full, width: Int(g.screenSize.width.rounded()),
                                          height: Int(g.screenSize.height.rounded())) else {
            throw MirrorError.phoneNotConnected(detail: "capture produced an empty image")
        }
        counter += 1
        return Screenshot(full: full, model: model, geometry: g, frameID: counter)
    }
}
```

- [ ] **Step 2: Add a `shot` subcommand**

In `Sources/iphone-mcp/main.swift`, add before `default:`:
```swift
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
```
and update the usage string to `usage: iphone-mcp [serve|status|shot <file> [--full]]`.

- [ ] **Step 3: Verify on the live window (bezel crop check)**

Run: `swift build -c release 2>&1 | tail -2 && .build/release/iphone-mcp shot /tmp/iphone-shot.png && .build/release/iphone-mcp shot /tmp/iphone-shot-full.png --full`
Expected: `wrote … 364x791 (full 728x1582)` (±1 px in height). Open `/tmp/iphone-shot.png` with the Read tool: the image must start exactly at the phone screen edge — **no black bezel band on any side, and the status bar fully visible**. If a band remains or content is clipped, measure the content bounds of the `--full` image and correct `PhoneGeometry.bezel`, updating `GeometryTests` expectations to match.

- [ ] **Step 4: Verify capture works while the window is behind other windows**

With another app covering the Mirroring window, rerun Step 3's first command. Expected: same output, image shows the phone (spike verified this, including minimized).

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "Add ScreenCaptureKit capturer with bezel crop and shot command

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 7: Takeover executor

**Files:**
- Create: `Sources/IPhoneMCPCore/Takeover.swift`
- Modify: `Sources/iphone-mcp/main.swift` (temporary `press` case, replaced in Task 8)

**Interfaces:**
- Consumes: `InputStep`, `IdleGate`, `MirrorWindow`, `MirrorTarget`, `MirrorError`.
- Produces: `public actor Takeover { struct Config { idleThreshold, idleMaxWait, activateTimeout: Double; settleAfterActivateMs: Int }; init(config: Config = .init()); func run(_ steps: [InputStep], on target: MirrorTarget) async throws }`

- [ ] **Step 1: Implement Takeover**

`Sources/IPhoneMCPCore/Takeover.swift`:
```swift
import AppKit
import CoreGraphics

/// Runs input with iPhone Mirroring active, then restores the user's cursor and frontmost app.
/// Background delivery (postToPid, SkyLight records) was proven not to work on macOS 27 — see spec §2.
public actor Takeover {
    public struct Config: Sendable {
        public var idleThreshold = 0.75
        public var idleMaxWait = 3.0
        public var activateTimeout = 1.0
        public var settleAfterActivateMs = 250
        public init() {
            if let v = ProcessInfo.processInfo.environment["IPHONE_MCP_SETTLE_MS"], let ms = Int(v) {
                settleAfterActivateMs = ms
            }
        }
    }

    let config: Config
    private var lastPost: Date?

    public init(config: Config = Config()) { self.config = config }

    public func run(_ steps: [InputStep], on target: MirrorTarget) async throws {
        await waitForIdle()
        let prevPID = MirrorWindow.frontmostOwnerPID()
        let savedCursor = CGEvent(source: nil)?.location ?? .zero
        let src = CGEventSource(stateID: .hidSystemState)
        var buttonDownAt: CGPoint?
        defer {
            if let p = buttonDownAt { Self.mouse(.leftMouseUp, p, src) }   // never leave the button held
            CGWarpMouseCursorPosition(savedCursor)
            CGAssociateMouseAndMouseCursorPosition(1)
            if let prev = prevPID, prev != target.pid { MirrorWindow.setFrontmost(prev) }
            lastPost = Date()
        }
        try await activate(target)
        for step in steps {
            switch step {
            case .move(let p):
                Self.mouse(.mouseMoved, p, src)
            case .down(let p):
                guard let owner = MirrorWindow.topmostOwner(at: p), owner.pid == target.pid else {
                    throw MirrorError.targetOccluded(owner: MirrorWindow.topmostOwner(at: p)?.name ?? "nothing (off-screen)")
                }
                Self.mouse(.leftMouseDown, p, src); buttonDownAt = p
            case .drag(let p):
                Self.mouse(.leftMouseDragged, p, src); buttonDownAt = p
            case .up(let p):
                Self.mouse(.leftMouseUp, p, src); buttonDownAt = nil
            case .key(let code, let down, let flags):
                let e = CGEvent(keyboardEventSource: src, virtualKey: code, keyDown: down)
                e?.flags = CGEventFlags(rawValue: flags)
                e?.post(tap: .cghidEventTap)
            case .text(let units):
                for down in [true, false] {
                    var u = units
                    let e = CGEvent(keyboardEventSource: src, virtualKey: 0, keyDown: down)
                    e?.keyboardSetUnicodeString(stringLength: u.count, unicodeString: &u)
                    e?.post(tap: .cghidEventTap)
                }
            case .sleep(let ms):
                try await Task.sleep(nanoseconds: UInt64(max(ms, 0)) * 1_000_000)
            }
        }
    }

    static func mouse(_ type: CGEventType, _ p: CGPoint, _ src: CGEventSource?) {
        CGEvent(mouseEventSource: src, mouseType: type, mouseCursorPosition: p, mouseButton: .left)?
            .post(tap: .cghidEventTap)
    }

    func waitForIdle() async {
        let types: [CGEventType] = [.mouseMoved, .leftMouseDown, .leftMouseDragged, .rightMouseDown,
                                    .keyDown, .scrollWheel, .flagsChanged]
        let deadline = Date().addingTimeInterval(config.idleMaxWait)
        while Date() < deadline {
            let ago = types.map { CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: $0) }.min() ?? 99
            let ours = lastPost.map { Date().timeIntervalSince($0) }
            if !IdleGate.userIsActive(lastInputAgo: ago, ourLastPostAgo: ours, threshold: config.idleThreshold) { return }
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
    }

    func activate(_ t: MirrorTarget) async throws {
        if t.minimized {
            MirrorWindow.unminimize(t)
            try await Task.sleep(nanoseconds: 400_000_000)
        }
        if MirrorWindow.isFrontmost(t) { return }
        let deadline = Date().addingTimeInterval(config.activateTimeout)
        while Date() < deadline {
            MirrorWindow.setFrontmost(t.pid)
            MirrorWindow.raise(t)
            try await Task.sleep(nanoseconds: 80_000_000)
            if MirrorWindow.isFrontmost(t) {
                try await Task.sleep(nanoseconds: UInt64(config.settleAfterActivateMs) * 1_000_000)
                return
            }
        }
        let owner = MirrorWindow.topmostOwner(at: CGPoint(x: t.frame.midX, y: t.frame.midY))?.name ?? "unknown"
        throw MirrorError.activationTimeout(detail: "the front window belongs to \(owner)")
    }
}
```

- [ ] **Step 2: Add a temporary `press` subcommand for live verification**

In `main.swift`, add before `default:`:
```swift
case "press":   // temporary; replaced by `call` in Task 8
    let code: UInt16 = argv.count > 1 && argv[1] == "home" ? KeyCode.one : KeyCode.three
    do {
        let t = try MirrorWindow.locate()
        try MirrorWindow.requireLive(t)
        let t0 = Date()
        try await Takeover().run(EventPlan.keyCombo(code, [.command]), on: t)
        print("ok in \(Int(Date().timeIntervalSince(t0) * 1000)) ms")
    } catch let e as MirrorError {
        print("\(e.code): \(e.message)"); exit(1)
    }
```

- [ ] **Step 3: Live verification (harmless: Spotlight then Home)**

Make another app frontmost (e.g. `open -a "Google Chrome"`), keep hands off the mouse, then run:
`swift build -c release 2>&1 | tail -2 && .build/release/iphone-mcp press spotlight && sleep 1 && .build/release/iphone-mcp shot /tmp/after-spotlight.png && .build/release/iphone-mcp press home && sleep 1 && .build/release/iphone-mcp shot /tmp/after-home.png`

Expected: both `press` print `ok in N ms` with N < 800; `/tmp/after-spotlight.png` shows iOS Spotlight; `/tmp/after-home.png` shows a home screen; afterwards Chrome is still frontmost (check `osascript -e 'tell application "System Events" to name of first process whose frontmost is true'`). If N ≥ 800, note it for Task 10 tuning; do not change defaults here.

- [ ] **Step 4: Verify the occlusion guard cannot click other apps**

No code change: confirm by reading `Takeover.run` that every `.down` is preceded by the `topmostOwner` check and that `defer` releases a held button. (A live test would require clicking under another window; skip it.)

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "Add takeover executor with idle wait, activation, hit-test guard and restore

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 8: Args, Log and PhoneTools (tool surface), `call` subcommand

**Files:**
- Create: `Sources/IPhoneMCPCore/Args.swift`, `Sources/IPhoneMCPCore/Log.swift`, `Sources/IPhoneMCPCore/PhoneTools.swift`, `Tests/IPhoneMCPCoreTests/ArgsTests.swift`, `Tests/IPhoneMCPCoreTests/PhoneToolsTests.swift`
- Modify: `Sources/iphone-mcp/main.swift` (replace `press` case with `call`)

**Interfaces:**
- Consumes: everything above; MCP types `Tool`, `Value`, `CallTool.Result`, `Tool.Content`.
- Produces:
  - `public struct Args { init(_: [String: Value]); func double(_:) throws -> Double; func int(_:default:range:) throws -> Int; func optionalInt(_:) throws -> Int?; func string(_:) throws -> String; func bool(_:default:) throws -> Bool }`
  - `public final class PhoneTools { init(readOnly: Bool); let definitions: [Tool]; func call(_ name: String, _ arguments: [String: Value]) async -> CallTool.Result; static func firstText(_: CallTool.Result) -> String; static let instructions: String }`

- [ ] **Step 1: Write failing tests**

`Tests/IPhoneMCPCoreTests/ArgsTests.swift`:
```swift
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
}
```

`Tests/IPhoneMCPCoreTests/PhoneToolsTests.swift`:
```swift
import MCP
import Testing
@testable import IPhoneMCPCore

@Suite struct PhoneToolsTests {
    @Test func fullToolSurface() {
        let names = Set(PhoneTools(readOnly: false).definitions.map(\.name))
        #expect(names == ["screenshot", "screenshot_text", "tap_text", "tap", "long_press", "swipe", "drag",
                          "type_text", "press_key", "home", "app_switcher", "spotlight", "launch_app", "status"])
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
        let r = await PhoneTools(readOnly: true).call("tap", ["x": .int(1), "y": .int(1)])
        #expect(r.isError == true)
        #expect(PhoneTools.firstText(r).hasPrefix("INVALID_ARGUMENT"))
    }

    @Test func badArgumentsFailBeforeTouchingTheSystem() async {
        let r = await PhoneTools(readOnly: false).call("press_key", ["key": .string("f13")])
        #expect(r.isError == true)
        #expect(PhoneTools.firstText(r).hasPrefix("INVALID_ARGUMENT"))
    }
}
```

- [ ] **Step 2: Run to verify failure**

Run: `swift test --filter 'ArgsTests|PhoneToolsTests' 2>&1 | tail -5`
Expected: compile failure — `cannot find 'Args'`.

- [ ] **Step 3: Implement Args and Log**

`Sources/IPhoneMCPCore/Args.swift`:
```swift
import MCP

public struct Args {
    let raw: [String: Value]
    public init(_ raw: [String: Value]) { self.raw = raw }

    func present(_ k: String) -> Value? {
        guard let v = raw[k], v != .null else { return nil }
        return v
    }

    public func double(_ k: String) throws -> Double {
        guard let v = present(k) else { throw MirrorError.invalidArgument("missing required argument \"\(k)\"") }
        let d: Double?
        switch v {
        case .int(let i): d = Double(i)
        case .double(let x): d = x
        default: d = nil
        }
        guard let d, d.isFinite else { throw MirrorError.invalidArgument("\"\(k)\" must be a number") }
        return d
    }

    public func int(_ k: String, default def: Int, range: ClosedRange<Int>) throws -> Int {
        guard present(k) != nil else { return def }
        let d = try double(k)
        guard d == d.rounded(), let i = Int(exactly: d), range.contains(i) else {
            throw MirrorError.invalidArgument("\"\(k)\" must be an integer in \(range.lowerBound)...\(range.upperBound)")
        }
        return i
    }

    public func optionalInt(_ k: String) throws -> Int? {
        guard present(k) != nil else { return nil }
        return try int(k, default: 0, range: Int.min...Int.max)
    }

    public func string(_ k: String) throws -> String {
        guard let v = present(k) else { throw MirrorError.invalidArgument("missing required argument \"\(k)\"") }
        guard case .string(let s) = v else { throw MirrorError.invalidArgument("\"\(k)\" must be a string") }
        return s
    }

    public func bool(_ k: String, default def: Bool) throws -> Bool {
        guard let v = present(k) else { return def }
        guard case .bool(let b) = v else { throw MirrorError.invalidArgument("\"\(k)\" must be true or false") }
        return b
    }
}
```

`Sources/IPhoneMCPCore/Log.swift`:
```swift
import Foundation

/// Optional action log: tool name and argument KEYS only — never values (type_text may be private), never images.
enum Log {
    static let path = ProcessInfo.processInfo.environment["IPHONE_MCP_LOG"]

    static func action(_ name: String, keys: [String], outcome: String) {
        guard let path else { return }
        let line = "\(ISO8601DateFormatter().string(from: Date())) \(name) [\(keys.sorted().joined(separator: ","))] \(outcome)\n"
        if let h = FileHandle(forWritingAtPath: path) {
            h.seekToEndOfFile(); h.write(line.data(using: .utf8)!); try? h.close()
        } else {
            try? line.write(toFile: path, atomically: true, encoding: .utf8)
        }
    }
}
```

- [ ] **Step 4: Implement PhoneTools**

`Sources/IPhoneMCPCore/PhoneTools.swift`:
```swift
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

    public let definitions: [Tool]
    let takeover = Takeover()
    let capturer = Capturer()

    public init(readOnly: Bool) {
        let all = Self.allDefinitions()
        definitions = readOnly ? all.filter { Self.readOnlyNames.contains($0.name) } : all
    }

    // MARK: schema helpers

    static func schema(_ props: [(String, String, String)], required: [String] = [], screenshotFlag: Bool = true) -> Value {
        var p: [String: Value] = [:]
        for (name, type, desc) in props { p[name] = .object(["type": .string(type), "description": .string(desc)]) }
        if screenshotFlag {
            p["return_screenshot"] = .object(["type": .string("boolean"),
                "description": .string("Return a settled screenshot after acting (default true).")])
        }
        return .object(["type": .string("object"), "properties": .object(p), "required": .array(required.map { .string($0) })])
    }

    static func allDefinitions() -> [Tool] {
        let xy = [("x", "number", "X in 1x screenshot pixels"), ("y", "number", "Y in 1x screenshot pixels")]
        return [
            Tool(name: "screenshot", description: "Capture the phone screen as PNG. Coordinates for all tools are in the 1x image's pixels even when scale=2.",
                 inputSchema: schema([("scale", "integer", "1 (default) or 2 for fine print")], screenshotFlag: false)),
            Tool(name: "screenshot_text", description: "OCR the phone screen; returns [{text,x,y,w,h,confidence}] in 1x coordinates, no image.",
                 inputSchema: schema([], screenshotFlag: false)),
            Tool(name: "tap_text", description: "Find on-screen text by OCR (exact, then case-insensitive substring) and tap its centre. Errors if absent or ambiguous; pass occurrence (1-based) to choose.",
                 inputSchema: schema([("text", "string", "Label to tap"), ("occurrence", "integer", "1-based match index")], required: ["text"])),
            Tool(name: "tap", description: "Tap at (x, y).", inputSchema: schema(xy, required: ["x", "y"])),
            Tool(name: "long_press", description: "Press and hold at (x, y).",
                 inputSchema: schema(xy + [("duration_ms", "integer", "Hold time, 100-5000, default 800")], required: ["x", "y"])),
            Tool(name: "swipe", description: "Swipe/scroll from (x1,y1) to (x2,y2); movement starts immediately so it never becomes a long-press.",
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
            result = try await dispatch(name, Args(arguments))
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
            guard !s.isEmpty else { throw MirrorError.invalidArgument("text must not be empty") }
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
            guard !app.isEmpty else { throw MirrorError.invalidArgument("name must not be empty") }
            plan = .steps("launched \"\(app)\" via Spotlight") { _, _ in
                EventPlan.keyCombo(KeyCode.three, [.command]) + [.sleep(ms: 700)] + EventPlan.typeText(app)
                    + [.sleep(ms: 700)] + EventPlan.keyCombo(KeyCode.returnKey)
            }
        default: throw MirrorError.invalidArgument("unknown tool \"\(name)\"")
        }
        let wantShot = try a.bool("return_screenshot", default: true)

        try Permissions.require()
        let t = try MirrorWindow.locate()
        try MirrorWindow.requireLive(t)

        switch plan {
        case .shot(let scale):
            let s = try await capturer.capture(t)
            return .init(content: [Self.image(scale == 2 ? s.full : s.model),
                                   Self.text("{\"width\":\(s.model.width),\"height\":\(s.model.height),\"frame_id\":\(s.frameID),\"coordinates\":\"1x\"}")])
        case .ocr:
            let s = try await capturer.capture(t)
            let lines = try OCR.recognize(s.full, outputScale: s.pixelsPerPoint)
            return .init(content: [Self.text(String(data: try JSONEncoder().encode(lines), encoding: .utf8)!)])
        case .tapText(let q, let occ):
            let s = try await capturer.capture(t)
            let line = try TextMatcher.find(q, in: try OCR.recognize(s.full, outputScale: s.pixelsPerPoint), occurrence: occ)
            let p = try t.geometry.toGlobal(x: Double(line.centerX), y: Double(line.centerY))
            return try await act(t, wantShot, "tapped \"\(line.text)\" at (\(line.centerX), \(line.centerY))",
                                 EventPlan.tap(p, from: Self.cursor()))
        case .steps(let summary, let build):
            return try await act(t, wantShot, summary, try build(t.geometry, Self.cursor()))
        }
    }

    static func cursor() -> CGPoint { CGEvent(source: nil)?.location ?? .zero }

    func act(_ t: MirrorTarget, _ wantShot: Bool, _ summary: String, _ steps: [InputStep]) async throws -> CallTool.Result {
        try await takeover.run(steps, on: t)
        guard wantShot else { return .init(content: [Self.text("ok: \(summary)")]) }
        let s = try await settledScreenshot()
        return .init(content: [Self.text("ok: \(summary); frame_id \(s.frameID)"), Self.image(s.model)])
    }

    /// Wait for iOS to start reacting (stream latency), then sample every 100 ms until stable (max 1.5 s).
    func settledScreenshot() async throws -> Screenshot {
        try await Task.sleep(nanoseconds: 300_000_000)
        let t = try MirrorWindow.locate()
        var prev = try await capturer.capture(t)
        let deadline = Date().addingTimeInterval(1.5)
        while Date() < deadline {
            try await Task.sleep(nanoseconds: 100_000_000)
            let cur = try await capturer.capture(t)
            if Settle.isSettled(prev.model, cur.model) { return cur }
            prev = cur
        }
        return prev
    }
}
```

- [ ] **Step 5: Run unit tests**

Run: `swift test 2>&1 | tail -3`
Expected: the whole suite passes (Tasks 1–8). Note: `badArgumentsFailBeforeTouchingTheSystem` must pass without permissions or Mirroring — it proves validation precedes system access.

- [ ] **Step 6: Replace `press` with `call` in main.swift**

Delete the `case "press":` block and add:
```swift
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
```
Add `import MCP` at the top of `main.swift`. Update usage to `usage: iphone-mcp [serve|status|shot <file> [--full]|call <tool> [json]]`.

- [ ] **Step 7: Live verification via `call` (harmless only)**

With another app frontmost and hands off the mouse:
```bash
swift build -c release 2>&1 | tail -2
B=.build/release/iphone-mcp
$B call status
$B call spotlight
$B call type_text '{"text":"test"}'
$B call screenshot_text | head -c 600
$B call press_key '{"key":"delete","return_screenshot":false}'
$B call home
$B call tap '{"x":9999,"y":1}'; echo "exit=$?"
```
Expected: `status` JSON shows `session":"ready"`; `spotlight`/`type_text`/`home` print `ok: …` plus an `[image]` path (Read the images: Spotlight open, "test" typed, then Home); `screenshot_text` JSON contains a line with `test`; the last command prints `OUT_OF_BOUNDS: …` and `exit=1` without moving the cursor.

- [ ] **Step 8: Commit**

```bash
git add -A
git commit -m "Add MCP tool surface with argument validation, settle and call command

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 9: MCP stdio server, smoke test, registration

**Files:**
- Modify: `Sources/iphone-mcp/main.swift` (add `serve` as default)
- Create: `scripts/smoke.sh`

**Interfaces:**
- Consumes: `PhoneTools(readOnly:)`, `PhoneTools.instructions`, MCP `Server`, `StdioTransport`, `ListTools`, `CallTool`.

- [ ] **Step 1: Write the failing smoke script**

`scripts/smoke.sh`:
```bash
#!/bin/bash
# Speaks raw JSON-RPC to the binary: initialize, initialized, tools/list. Prints the tool names.
set -euo pipefail
BIN="${1:-.build/release/iphone-mcp}"
{
  printf '%s\n' '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"smoke","version":"0"}}}'
  printf '%s\n' '{"jsonrpc":"2.0","method":"notifications/initialized"}'
  printf '%s\n' '{"jsonrpc":"2.0","id":2,"method":"tools/list"}'
  sleep 2
} | "$BIN" | grep -o '"name":"[a-z_]*"' | sort -u
```
Run: `chmod +x scripts/smoke.sh && swift build -c release 2>&1 | tail -1 && scripts/smoke.sh`
Expected: FAIL — no output / usage error, because `serve` does not exist yet.

- [ ] **Step 2: Implement serve mode**

In `main.swift`, replace the `default:` branch with:
```swift
case nil, "serve":
    let tools = PhoneTools(readOnly: ProcessInfo.processInfo.environment["IPHONE_MCP_READONLY"] == "1")
    let server = Server(name: "iphone-mcp", version: "0.1.0", instructions: PhoneTools.instructions,
                        capabilities: .init(tools: .init(listChanged: false)))
    try await server.start(transport: StdioTransport())
    await server.withMethodHandler(ListTools.self) { _ in .init(tools: tools.definitions) }
    await server.withMethodHandler(CallTool.self) { params in await tools.call(params.name, params.arguments ?? [:]) }
    await server.waitUntilCompleted()
default:
    FileHandle.standardError.write("usage: iphone-mcp [serve|status|shot <file> [--full]|call <tool> [json]|selftest]\n".data(using: .utf8)!)
    exit(2)
```
Confirm no `print` is reachable in the `serve` path (stdout is the JSON-RPC channel).

- [ ] **Step 3: Run the smoke test**

Run: `swift build -c release 2>&1 | tail -1 && scripts/smoke.sh`
Expected: 14 lines `"name":"app_switcher"` … `"name":"type_text"` — exactly the 14 tool names from Task 8. Then `IPHONE_MCP_READONLY=1 scripts/smoke.sh` → exactly `screenshot`, `screenshot_text`, `status` (plus `"name":"iphone-mcp"` from serverInfo is acceptable in both outputs; ignore it).

- [ ] **Step 4: Commit**

```bash
git add -A
git commit -m "Serve tools over MCP stdio; add JSON-RPC smoke test

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

- [ ] **Step 5: Register with Claude Code (user-level config change — confirm with the user first)**

```bash
claude mcp add iphone -- "$PWD/.build/release/iphone-mcp"
claude mcp list | grep iphone
```
Expected: `iphone: … ✓ Connected`.

---

### Task 10: On-device selftest, tuning, README

**Files:**
- Create: `Sources/iphone-mcp/SelfTest.swift`, `README.md`
- Modify: `Sources/iphone-mcp/main.swift` (add `selftest` case)

**Interfaces:**
- Consumes: `PhoneTools.call`, `PhoneTools.firstText`, `MirrorWindow.frontmostOwnerPID()`.
- Produces: `func runSelfTest() async -> Int32` (exit code = number of failures).

- [ ] **Step 1: Implement the selftest**

`Sources/iphone-mcp/SelfTest.swift`:
```swift
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
    await step("scroll results up", "swipe", ["x1": .int(182), "y1": .int(420), "x2": .int(182), "y2": .int(220)])
    await step("scroll results down", "swipe", ["x1": .int(182), "y1": .int(220), "x2": .int(182), "y2": .int(420)])
    for _ in 0..<4 { await step("delete", "press_key", ["key": .string("delete"), "return_screenshot": .bool(false)]) }
    await step("home", "home")
    await step("out-of-bounds rejected", "tap", ["x": .int(9999), "y": .int(1)],
               check: { $0.isError == true && PhoneTools.firstText($0).hasPrefix("OUT_OF_BOUNDS") })

    let frontAfter = MirrorWindow.frontmostOwnerPID()
    let c = CGEvent(source: nil)?.location ?? .zero
    let restored = frontAfter == frontBefore && hypot(c.x - cursorBefore.x, c.y - cursorBefore.y) < 2
    if !restored { failures += 1 }
    print("\(restored ? "PASS" : "FAIL")  user state restored (front pid \(frontBefore ?? -1) → \(frontAfter ?? -1), cursor Δ \(Int(hypot(c.x - cursorBefore.x, c.y - cursorBefore.y))) pt)")
    print(failures == 0 ? "ALL PASS" : "\(failures) FAILURE(S)")
    return failures
}
```

In `main.swift`, add before `default:`:
```swift
case "selftest":
    exit(await runSelfTest())
```

- [ ] **Step 2: Run the selftest with the phone connected (user present, hands off)**

Make Chrome (or any app) frontmost, then: `swift build -c release 2>&1 | tail -1 && .build/release/iphone-mcp selftest`
Expected: every line `PASS`, final `ALL PASS`. Record the per-step ms. If an action step consistently fails because input is dropped right after activation, rerun with `IPHONE_MCP_SETTLE_MS=500`; if that fixes it, change the default `settleAfterActivateMs` in `Takeover.Config` to the smallest value that passes 3 consecutive runs, and commit that change with the timings in the message.

- [ ] **Step 3: Minimized-window check (Review Focus #5)**

Minimize the iPhone Mirroring window (⌘M on it), make another app frontmost, then run: `.build/release/iphone-mcp call spotlight && .build/release/iphone-mcp call home`
Expected: both `ok: …`; the window is restored and the actions take effect. Then also check landscape is at least not destructive: if the user has a landscape-only app handy, note whether `call screenshot` crops correctly — record the observation in the README "Known limitations" (no code change in v1).

- [ ] **Step 4: Write README.md**

```markdown
# iphone-mcp

MCP server that lets Claude Code see and operate your iPhone through macOS **iPhone Mirroring**.

## Install
    swift build -c release
    claude mcp add iphone -- "$PWD/.build/release/iphone-mcp"

Requires macOS 15+, iPhone Mirroring connected, and **Screen Recording + Accessibility** granted to the app
that launches Claude Code (Claude desktop app or your terminal). `iphone-mcp status` shows what is missing.

## Tools
screenshot, screenshot_text (OCR), tap_text, tap, long_press, swipe, drag, type_text, press_key,
home, app_switcher, spotlight, launch_app, status. Coordinates are pixels of the 1x screenshot.

## How it works
Screenshots are captured in the background (ScreenCaptureKit). iPhone Mirroring ignores input unless it is
the active app, so each action briefly activates it (~0.3–0.5 s), posts real HID events, then restores your
cursor and previous app. Typing during that moment would go to the phone; actions wait for ~0.75 s of
idleness first.

## Safety
- `IPHONE_MCP_READONLY=1` exposes only screenshot, screenshot_text, status.
- Leave input tools un-allowlisted in Claude Code to approve every action.
- `IPHONE_MCP_LOG=/path/file` logs tool names and argument keys only.

## Debugging
    iphone-mcp status | shot out.png [--full] | call <tool> '<json>' | selftest
    scripts/smoke.sh

## Known limitations
No multi-touch (pinch/rotate). Landscape apps: bezel crop assumes portrait insets (see selftest notes).
Not usable while you are actively working in the same instant an action fires.
```

- [ ] **Step 5: Run the full unit suite and smoke test once more**

Run: `swift test 2>&1 | tail -2 && swift build -c release 2>&1 | tail -1 && scripts/smoke.sh | wc -l`
Expected: all tests pass; smoke prints 14 (or 15 including `iphone-mcp`) lines.

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "Add on-device selftest and README

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

- [ ] **Step 7: End-to-end (user, new Claude Code session)**

Ask the user to start a fresh Claude Code session and say: "Use the iphone tools: open Settings and tell me the iOS version." Expected: Claude uses `launch_app`/`tap_text`/`screenshot` and reports the version; the user's cursor and frontmost app are restored after each step.
