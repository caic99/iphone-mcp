import Foundation

/// Resumes the caller with whichever finishes first: the operation, or the timeout. A task group would
/// wait for its children on exit, and a hung ScreenCaptureKit call ignores cancellation, so the losing
/// work is cancelled and abandoned instead.
public func withTimeout<T>(seconds: Double, onTimeout: Error, _ operation: @escaping @Sendable () async throws -> T) async throws -> T {
    try await withCheckedThrowingContinuation { (cont: CheckedContinuation<T, Error>) in
        let gate = OnceGate()
        let work = Task.detached {
            do {
                let v = try await operation()
                if gate.claim() { cont.resume(returning: v) }
            } catch {
                if gate.claim() { cont.resume(throwing: error) }
            }
        }
        Task.detached {
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            if gate.claim() { work.cancel(); cont.resume(throwing: onTimeout) }
        }
    }
}

final class OnceGate: @unchecked Sendable {
    private let lock = NSLock()
    private var done = false
    func claim() -> Bool {
        lock.lock(); defer { lock.unlock() }
        if done { return false }
        done = true
        return true
    }
}
