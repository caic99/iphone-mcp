import Foundation
import Testing
@testable import IPhoneMCPCore

@Suite struct RestorePolicyTests {
    let mirroring: pid_t = 100, userApp: pid_t = 200

    @Test func userAppInFrontIsRestored() {
        #expect(RestorePolicy.target(frontAtStart: userApp, mirroringPID: mirroring, lastRestored: nil, lastPostAgo: nil) == userApp)
    }

    @Test func backToBackActionsKeepTheUsersApp() {
        // Our previous restore has not landed yet, so Mirroring still looks frontmost.
        #expect(RestorePolicy.target(frontAtStart: mirroring, mirroringPID: mirroring, lastRestored: userApp, lastPostAgo: 0.4) == userApp)
    }

    @Test func userChoseMirroringThemselves() {
        #expect(RestorePolicy.target(frontAtStart: mirroring, mirroringPID: mirroring, lastRestored: userApp, lastPostAgo: 30) == nil)
        #expect(RestorePolicy.target(frontAtStart: mirroring, mirroringPID: mirroring, lastRestored: nil, lastPostAgo: nil) == nil)
    }
}
