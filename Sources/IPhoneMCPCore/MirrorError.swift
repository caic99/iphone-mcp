import Foundation

public enum MirrorError: Error, Equatable {
    case mirroringNotRunning
    case phoneNotConnected(detail: String)
    case permissionScreen(app: String)
    case permissionAX(app: String)
    case activationTimeout(detail: String)
    case targetOccluded(reason: String)
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
        case .targetOccluded(let reason):
            "Stopped before sending input: \(reason). Nothing more was sent."
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
