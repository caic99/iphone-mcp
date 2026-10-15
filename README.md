# iphone-mcp

MCP server that lets Claude Code see and operate your iPhone through macOS **iPhone Mirroring**.

## Install

```bash
swift build -c release
claude mcp add iphone -- "$PWD/.build/release/iphone-mcp"
```

Requires macOS 15+, iPhone Mirroring connected, and **Screen Recording + Accessibility** granted to the app
that launches Claude Code (Claude desktop app or your terminal). `iphone-mcp status` shows what is missing.

## Tools

screenshot, screenshot_text (OCR), tap_text, tap, long_press, scroll (wheel — use for lists), swipe (pages/flicks),
drag, type_text, press_key,
home, app_switcher, spotlight, launch_app, status. Coordinates are pixels of the 1x screenshot.
Action tools return compact OCR text by default (`return: "text"`, ~3x cheaper than an image);
pass `return: "image" | "both" | "none"` as needed — the image is added automatically when a screen has almost no text.

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

```bash
iphone-mcp status
iphone-mcp shot out.png [--full]
iphone-mcp call <tool> '<json>'
iphone-mcp selftest
scripts/smoke.sh
```

## Known limitations

- No multi-touch (pinch/rotate).
- Drag gestures do not scroll lists in iPhone Mirroring; `scroll` uses the scroll wheel with the cursor over the phone.
- Landscape apps: the bezel crop assumes the portrait insets (unverified in landscape).
- While your phone is in use (unlocked in hand), Mirroring pauses and every tool returns `PHONE_NOT_CONNECTED`.
- Not usable while you are actively working in the same instant an action fires.

## License

MIT — see [LICENSE](LICENSE).
