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
    private var lastRestored: pid_t?

    public init(config: Config = Config()) { self.config = config }

    /// `build` receives the window as re-read *after* the idle wait and activation (it may have moved,
    /// or the phone may have locked meanwhile) plus the cursor position, and returns the steps to post.
    public func run(on initial: MirrorTarget, build: (MirrorTarget, CGPoint) throws -> [InputStep]) async throws {
        await waitForIdle()
        let prevPID = RestorePolicy.target(frontAtStart: MirrorWindow.frontmostOwnerPID(), mirroringPID: initial.pid,
                                           lastRestored: lastRestored, lastPostAgo: lastPost.map { Date().timeIntervalSince($0) })
        let savedCursor = CGEvent(source: nil)?.location ?? .zero
        let src = CGEventSource(stateID: .hidSystemState)
        var buttonDownAt: CGPoint?
        defer {
            if let p = buttonDownAt { Self.mouse(.leftMouseUp, p, src) }   // never leave the button held
            CGWarpMouseCursorPosition(savedCursor)
            CGAssociateMouseAndMouseCursorPosition(1)
            if let prev = prevPID { Self.restoreFocus(to: prev) }
            lastRestored = prevPID
            lastPost = Date()
        }
        try await activate(initial)
        let target = try MirrorWindow.locate()
        try MirrorWindow.requireLive(target)
        let steps = try build(target, savedCursor)
        for step in steps {
            switch step {
            case .move(let p):
                Self.mouse(.mouseMoved, p, src)
            case .down(let p):
                guard let owner = MirrorWindow.topmostOwner(at: p), owner.pid == target.pid else {
                    throw MirrorError.targetOccluded(reason: "the point is covered by \(MirrorWindow.topmostOwner(at: p)?.name ?? "nothing (off-screen)")")
                }
                Self.mouse(.leftMouseDown, p, src); buttonDownAt = p
            case .drag(let p):
                Self.mouse(.leftMouseDragged, p, src); buttonDownAt = p
            case .up(let p):
                Self.mouse(.leftMouseUp, p, src); buttonDownAt = nil
            case .key(let code, let down, let flags):
                try Self.requireFocus(target)
                let e = CGEvent(keyboardEventSource: src, virtualKey: code, keyDown: down)
                e?.flags = CGEventFlags(rawValue: flags)
                e?.post(tap: .cghidEventTap)
            case .text(let units):
                try Self.requireFocus(target)
                for down in [true, false] {
                    var u = units
                    let e = CGEvent(keyboardEventSource: src, virtualKey: 0, keyDown: down)
                    e?.keyboardSetUnicodeString(stringLength: u.count, unicodeString: &u)
                    e?.post(tap: .cghidEventTap)
                }
            case .scroll(let p, let dy):
                // A scroll goes to whatever window is under the real cursor: confirm it is ours, right here.
                let c = CGEvent(source: nil)?.location ?? .zero
                guard hypot(c.x - p.x, c.y - p.y) <= 2 else {
                    throw MirrorError.targetOccluded(reason: "the cursor was moved away (to \(Int(c.x)),\(Int(c.y))) — user activity")
                }
                guard let owner = MirrorWindow.topmostOwner(at: p), owner.pid == target.pid else {
                    throw MirrorError.targetOccluded(reason: "the point is covered by \(MirrorWindow.topmostOwner(at: p)?.name ?? "nothing (off-screen)")")
                }
                try Self.requireFocus(target)
                let e = CGEvent(scrollWheelEvent2Source: src, units: .pixel, wheelCount: 1, wheel1: dy, wheel2: 0, wheel3: 0)
                e?.location = p
                e?.post(tap: .cghidEventTap)
            case .sleep(let ms):
                try await Task.sleep(nanoseconds: UInt64(max(ms, 0)) * 1_000_000)
            }
        }
    }

    /// Keys go to whichever app has focus, so stop the moment Mirroring loses it.
    static func requireFocus(_ t: MirrorTarget) throws {
        guard MirrorWindow.isFrontmost(t) else {
            let owner = MirrorWindow.frontmostOwnerPID().flatMap { NSRunningApplication(processIdentifier: $0)?.localizedName } ?? "another app"
            throw MirrorError.targetOccluded(reason: "iPhone Mirroring lost focus to \(owner)")
        }
    }

    /// Give focus back and confirm it landed (re-asserting for up to 500 ms).
    static func restoreFocus(to pid: pid_t) {
        for _ in 0..<10 {
            MirrorWindow.setFrontmost(pid)
            usleep(50_000)
            if MirrorWindow.frontmostOwnerPID() == pid { return }
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
