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
        let candidates = windowList(onScreenOnly: false)
            .filter { ownerPID($0) == pid && layer($0) == 0 }
            .compactMap { w -> WindowCandidate? in
                guard let id = (w[kCGWindowNumber as String] as? NSNumber)?.uint32Value else { return nil }
                return WindowCandidate(id: id, title: w[kCGWindowName as String] as? String ?? "", bounds: bounds(w))
            }
        guard let w = WindowPicker.pick(candidates, appName: appName) else {
            throw MirrorError.phoneNotConnected(detail: "no phone window yet — iPhone Mirroring may still be connecting")
        }
        let id = w.id
        let frame = w.bounds
        let axWins = (axCopy(AXUIElementCreateApplication(pid), kAXWindowsAttribute) as? [AXUIElement]) ?? []
        let ax = axWins.first { axFrame($0)?.size == frame.size } ?? axWins.first
        let minimized = ax.flatMap { axCopy($0, kAXMinimizedAttribute) as? Bool } ?? false
        return MirrorTarget(pid: pid, windowID: id, frame: frame, axWindow: ax, minimized: minimized)
    }

    static let contentRoles: Set<String> = ["AXStaticText", "AXButton", "AXTextField", "AXSecureTextField", "AXImage"]

    public static func session(_ t: MirrorTarget) -> SessionState {
        guard let root = t.axWindow, axCopy(root, kAXChildrenAttribute) is [AXUIElement] else {
            return SessionState.from(nodes: [], rootReadable: false)
        }
        var nodes: [(role: String, text: String)] = []
        var queue: [(AXUIElement, Int)] = [(root, 0)]
        while !queue.isEmpty {
            let (el, depth) = queue.removeFirst()
            // The hover toolbar (Home Screen / App Switcher buttons) lives in the title-bar inset and is
            // present while the stream is live; only native UI drawn over the phone screen means "blocked".
            let overScreen = axFrame(el).map { t.geometry.screenContains(global: CGPoint(x: $0.midX, y: $0.midY)) } ?? true
            if depth > 0, overScreen, let role = axCopy(el, kAXRoleAttribute) as? String, contentRoles.contains(role) {
                let text = [kAXTitleAttribute, kAXValueAttribute, kAXDescriptionAttribute]
                    .compactMap { axCopy(el, $0) as? String }.first { !$0.isEmpty } ?? ""
                nodes.append((role, text))
            }
            if depth < 8, let kids = axCopy(el, kAXChildrenAttribute) as? [AXUIElement] {
                queue += kids.map { ($0, depth + 1) }
            }
        }
        return SessionState.from(nodes: nodes, rootReadable: true)
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
