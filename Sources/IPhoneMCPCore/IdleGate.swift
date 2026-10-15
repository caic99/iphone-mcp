public enum IdleGate {
    /// - lastInputAgo: seconds since the last HID event of any source (includes our own posts).
    /// - ourLastPostAgo: seconds since this process last finished posting, nil if never.
    public static func userIsActive(lastInputAgo: Double, ourLastPostAgo: Double?, threshold: Double) -> Bool {
        guard lastInputAgo < threshold else { return false }
        if let ours = ourLastPostAgo, lastInputAgo >= ours - 0.05 { return false }   // the latest input was ours
        return true
    }
}
