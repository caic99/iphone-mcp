# iphone-mcp — design

Date: 2026-10-14 · Status: approved in chat, awaiting written-spec review

## 1. Goal

Let an LLM (Claude Code) operate the user's iPhone through macOS **iPhone Mirroring**
(`com.apple.ScreenContinuity`): see the screen and tap, swipe, drag and type.

Success criteria:
- Claude Code, with the server registered, can complete a simple phone task end to end
  (e.g. "open Settings and tell me the iOS version").
- Every input action leaves the user's cursor position and frontmost app as it found them.
- No click is ever delivered to a window other than iPhone Mirroring.

Non-goals (v1): running fully in the background, multi-touch (pinch/rotate), menu-bar UI,
multiple phones, recording/replay, its own agent loop.

## 2. Feasibility findings (spike, macOS 27.0.1)

| Probe | Result |
|---|---|
| ScreenCaptureKit window capture | Works when the window is covered **and when minimized**; 100–180 ms. Needs `NSApplication.shared` first or CGS init asserts. |
| `CGEventPostToPid` mouse events (with/without window-id fields) | Ignored. |
| SkyLight focus record + `SLEventPostToPid` | Ignored. |
| SkyLight mouse event records (phone-harness technique) | Requires `_SLPSSetFrontProcessWithOptions`, which **activates** Mirroring (steals keyboard focus); ~1 in 6 taps landed; restoring focus right after kills the tap. Rejected. |
| Takeover: AX `frontmost` activation + HID-tap CGEvents + restore | Works reliably for tap, swipe, ⌘-shortcuts and Unicode typing. |
| `NSRunningApplication.activate` from a CLI process | Does not activate; AX `kAXFrontmostAttribute` does. |
| Slow-starting drag on an icon | iOS treats it as long-press → icon move. Swipes must move immediately. |

Existing projects reviewed: jfarcand/mirroir-mcp (focus-taking, heavy), nickatnight96/iphone-mirror-mcp
(focus-taking, best quirk documentation), ShawnPana/phone-harness (SkyLight background path, see above).
Decision: build fresh in Swift, borrowing documented quirk handling.

## 3. Architecture

Single SwiftPM package producing one CLI binary `iphone-mcp`, an MCP server over **stdio**
(official `modelcontextprotocol/swift-sdk`), launched on demand by Claude Code:

```
claude mcp add iphone -- ~/Documents/mnt/iphone-mcp/.build/release/iphone-mcp
```

| Unit | Responsibility | Depends on |
|---|---|---|
| `MirrorWindow` | Locate process + main window, unminimize, frame, connected/locked detection | AX, CGWindowList |
| `Capturer` | SCK capture of the window → `CGImage` (2×), crop to phone screen, 1× downscale, PNG | MirrorWindow |
| `Takeover` | Actor; runs an input block with Mirroring active, then restores user state | MirrorWindow |
| `Input` | Builds and posts HID-tap mouse/key event sequences; only callable inside `Takeover` | Takeover |
| `OCR` | Vision text recognition → lines with boxes | — |
| `Geometry` | Pure: screenshot px ↔ global screen points, bounds checks | — |
| `Tools` | MCP tool definitions, argument validation, error mapping | all |

## 4. Coordinates

- The model's coordinate space is **pixels of the 1× screenshot it received**, origin at the
  phone screen's top-left (bezel cropped).
- Phone-screen rect inside the window: from the AX content element if exposed, else a fixed
  inset measured once and stored as a constant.
- Conversion to global points always uses the **live** window frame, so a moved window is fine.
- Out-of-range coordinates → `OUT_OF_BOUNDS`.

## 5. Tools (v1)

| Tool | Args | Notes |
|---|---|---|
| `screenshot` | `scale` (1\|2, default 1) | Returns PNG + size |
| `screenshot_text` | — | OCR lines `{text,x,y,w,h,confidence}`, no image |
| `tap_text` | `text`, `occurrence?` | Exact (trimmed) then case-insensitive substring; multiple matches without `occurrence` → `TEXT_AMBIGUOUS` listing them |
| `tap` | `x,y` | |
| `long_press` | `x,y,duration_ms=800` | |
| `swipe` | `x1,y1,x2,y2,duration_ms=250` | Movement starts immediately (no long-press) |
| `drag` | `x1,y1,x2,y2,hold_ms=600,duration_ms=500` | Deliberate hold then move (icons, sliders) |
| `type_text` | `text` | Unicode key events, one takeover |
| `press_key` | `key` ∈ return, delete, escape, tab, up, down, left, right | |
| `home` / `app_switcher` / `spotlight` | — | ⌘1 / ⌘2 / ⌘3 |
| `launch_app` | `name` | ⌘3, type name, Return — one takeover |
| `status` | — | running / connected / minimized, permissions, frame |

All action tools accept `return_screenshot` (default `true`): after acting, wait for settle and
return a fresh 1× screenshot.

`IPHONE_MCP_READONLY=1` registers only `screenshot`, `screenshot_text`, `status`.
Tool descriptions instruct the model to ask the user before payments, sending messages or deleting.

## 6. Takeover sequence

All input is serialized through the `Takeover` actor:

1. **Idle wait**: if `CGEventSourceSecondsSinceLastEventType(.combinedSessionState, any)` < 0.75 s,
   poll until idle, max 3 s, then proceed.
2. **Save** frontmost app (pid) and cursor location.
3. **Prepare**: unminimize via AX if needed; if the window shows the connect/locked screen →
   `PHONE_NOT_CONNECTED`.
4. **Activate**: set AX `kAXFrontmostAttribute` on Mirroring; poll the same attribute until true
   (timeout 1 s → `ACTIVATION_TIMEOUT`); then settle delay (default 250 ms, tuned during
   implementation).
5. **Hit-test guard** before every mouse-down: topmost on-screen layer-0 window containing the
   point must be the Mirroring window, else abort with `TARGET_OCCLUDED`.
6. **Post** via `.cghidEventTap`:
   - mouse: a few `mouseMoved` steps to the start point, `leftMouseDown`, `leftMouseDragged`
     steps, `leftMouseUp`;
   - keys: modifiers as real held keys (⌘ keycode 55 down … up) plus flags; text via
     `keyboardSetUnicodeString` per UTF-16 unit.
7. **Restore** (in `defer`, always): `CGWarpMouseCursorPosition` back, then AX-frontmost the saved
   app (skipped if it was Mirroring).

Accepted risk: user keystrokes during the ~300–500 ms window reach the phone.

## 7. Screenshots, settle, OCR

- Capture: `SCScreenshotManager.captureImage` with `SCContentFilter(desktopIndependentWindow:)`,
  `showsCursor = false`, 2× resolution; crop; 1× copy for the model.
- Settle: sample every 100 ms until two consecutive frames differ by < 0.5 % of pixels
  (per-pixel RGB delta > 60), or 1.5 s elapses.
- OCR: `VNRecognizeTextRequest`, `.accurate`, languages `zh-Hans, zh-Hant, en`,
  `usesLanguageCorrection = false`; run on the 2× image, boxes mapped to 1× coords; sorted
  top-to-bottom then left-to-right.
- Privacy: images/text go only to the MCP client. Nothing written to disk except an optional
  action-name log (`IPHONE_MCP_LOG=<path>`), never images.

## 8. Permissions and errors

- TCC attribution goes to the responsible launching app (Claude desktop app or terminal).
  Checked at startup and in `status` with `CGPreflightScreenCaptureAccess` / `AXIsProcessTrusted`;
  never prompts.
- Error codes (MCP tool errors with a one-line remedy): `MIRRORING_NOT_RUNNING`,
  `PHONE_NOT_CONNECTED`, `PERMISSION_SCREEN`, `PERMISSION_AX`, `ACTIVATION_TIMEOUT`,
  `TARGET_OCCLUDED`, `OUT_OF_BOUNDS`, `TEXT_NOT_FOUND`, `TEXT_AMBIGUOUS`.

## 9. Testing

- `swift test` (no phone): Geometry mapping (crop, moved window, bounds), OCR match/ordering,
  frame-diff settle predicate, key-sequence building. Fixtures: generated images or a
  home-screen capture without private content.
- `iphone-mcp selftest` (phone connected, user present): screenshot → Spotlight → type "test" →
  OCR verifies "test" → swipe up then down inside the Spotlight results list (scrolls; never
  starts on a home-screen icon) → delete ×4 → home. Prints per-step timings.
- End to end: register with Claude Code; "open Settings and tell me the iOS version".
