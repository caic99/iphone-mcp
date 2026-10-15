import Testing
@testable import IPhoneMCPCore

@Suite struct TimeoutTests {
    @Test func fastOperationReturnsItsValue() async throws {
        let v = try await withTimeout(seconds: 1, onTimeout: MirrorError.phoneNotConnected(detail: "t")) { 7 }
        #expect(v == 7)
    }

    @Test func hungOperationThrowsTheTimeoutError() async {
        let clock = ContinuousClock(), start = clock.now
        await #expect(throws: MirrorError.phoneNotConnected(detail: "screen capture timed out")) {
            try await withTimeout(seconds: 0.2, onTimeout: MirrorError.phoneNotConnected(detail: "screen capture timed out")) {
                try await Task.sleep(nanoseconds: 5_000_000_000); return 1
            }
        }
        #expect(clock.now - start < .seconds(2))
    }

    @Test func operationErrorsPassThrough() async {
        await #expect(throws: MirrorError.mirroringNotRunning) {
            try await withTimeout(seconds: 1, onTimeout: MirrorError.phoneNotConnected(detail: "t")) { () async throws -> Int in
                throw MirrorError.mirroringNotRunning
            }
        }
    }
}
