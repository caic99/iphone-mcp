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

    public func choice(_ k: String, default def: String, allowed: [String]) throws -> String {
        guard present(k) != nil else { return def }
        let v = try string(k)
        guard allowed.contains(v) else {
            throw MirrorError.invalidArgument("\"\(k)\" must be one of: \(allowed.joined(separator: ", "))")
        }
        return v
    }
}
