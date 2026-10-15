import Foundation

public enum RestorePolicy {
    /// Which app gets focus back after an action. Focus restore is asynchronous, so in back-to-back
    /// actions Mirroring can still look frontmost when the next one starts; remember who we restored.
    public static func target(frontAtStart: pid_t?, mirroringPID: pid_t, lastRestored: pid_t?, lastPostAgo: Double?) -> pid_t? {
        if let f = frontAtStart, f != mirroringPID { return f }
        if let r = lastRestored, let ago = lastPostAgo, ago < 5 { return r }
        return nil   // the user had Mirroring in front themselves
    }
}
