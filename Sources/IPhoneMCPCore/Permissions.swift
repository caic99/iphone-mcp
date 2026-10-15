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
