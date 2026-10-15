import Testing
@testable import IPhoneMCPCore

actor Recorder {
    var items: [String] = []
    func add(_ s: String) { items.append(s) }
}

@Suite struct AsyncLockTests {
    @Test func concurrentBodiesNeverInterleave() async {
        let lock = AsyncLock(), rec = Recorder()
        async let a: Void = lock.withLock {
            await rec.add("a-start"); try? await Task.sleep(nanoseconds: 50_000_000); await rec.add("a-end")
        }
        async let b: Void = lock.withLock {
            await rec.add("b-start"); try? await Task.sleep(nanoseconds: 10_000_000); await rec.add("b-end")
        }
        _ = await (a, b)
        let items = await rec.items
        #expect(items == ["a-start", "a-end", "b-start", "b-end"] || items == ["b-start", "b-end", "a-start", "a-end"])
    }

    @Test func releasesAfterThrow() async {
        struct Boom: Error {}
        let lock = AsyncLock()
        _ = try? await lock.withLock { throw Boom() }
        let v = await lock.withLock { 42 }
        #expect(v == 42)
    }
}
