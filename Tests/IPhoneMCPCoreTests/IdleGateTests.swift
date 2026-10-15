import Testing
@testable import IPhoneMCPCore

@Suite struct IdleGateTests {
    @Test func idleWhenNoRecentInput() { #expect(!IdleGate.userIsActive(lastInputAgo: 2, ourLastPostAgo: nil, threshold: 0.75)) }
    @Test func activeWhenRecentInputAndWeNeverPosted() { #expect(IdleGate.userIsActive(lastInputAgo: 0.1, ourLastPostAgo: nil, threshold: 0.75)) }
    @Test func ourOwnLastEventIsNotUserActivity() { #expect(!IdleGate.userIsActive(lastInputAgo: 0.30, ourLastPostAgo: 0.32, threshold: 0.75)) }
    @Test func userInputAfterOursIsActivity() { #expect(IdleGate.userIsActive(lastInputAgo: 0.1, ourLastPostAgo: 0.5, threshold: 0.75)) }
}
