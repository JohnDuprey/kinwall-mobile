import Testing
@testable import KinwallKit

@Suite struct WatchLoadTests {
    enum Offline: Error { case unavailable }
    func unavailable<T>() async throws -> T { throw Offline.unavailable }

    @Test func emptyMembersFinishesLoading() async {
        var members: [Member] = []
        let phase = await WatchLoadPhase.completing { members = [] }
        #expect(phase == .loaded)
        #expect(members.isEmpty)
    }

    @Test func failedIdentityRequestFinishesWithError() async {
        var requestedCheck = false
        let phase = await WatchLoadPhase.completing {
            let _: Me = try await unavailable()
            requestedCheck = true
        }
        #expect(phase == .failed)
        #expect(!requestedCheck)
    }

    @Test func failedCheckRequestFinishesWithError() async {
        let phase = await WatchLoadPhase.completing {
            let _: TempCheck = try await unavailable()
        }
        #expect(phase == .failed)
    }

    @Test func retryClearsPreviousFailure() async {
        var phase = await WatchLoadPhase.completing { throw Offline.unavailable }
        #expect(phase == .failed)
        phase = await WatchLoadPhase.completing { }
        #expect(phase == .loaded)
    }
}
