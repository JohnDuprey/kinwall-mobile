import Foundation
import Testing
@testable import KinwallKit

// TokenRefresh: the app, its intents and the share extension refresh the same sign-in apart.
@Suite struct TokenRefreshTests {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    func tokens(_ refresh: String, expires: TimeInterval) -> OAuth.Tokens {
        OAuth.Tokens(baseURL: URL(string: "https://kinwall.family/")!, clientId: "c", accessToken: "a-\(refresh)", refreshToken: refresh,
                     expiresAt: now.addingTimeInterval(expires), scope: "kinwall:admin")
    }
    let gone = OAuthError(code: "invalid_grant", message: "used")

    @Test func currentTokensGoAsTheyAre() async throws {
        let t = tokens("r1", expires: 3600)
        let out = try await TokenRefresh.fresh(t, now: now, reread: { nil }, refresh: { _ in Issue.record("refreshed"); return t }, save: { _ in true })
        #expect(out == t)
    }

    @Test func aRefreshIsSavedBeforeUse() async throws {
        var saved: [OAuth.Tokens] = []
        let out = try await TokenRefresh.fresh(tokens("r1", expires: 60), now: now, reread: { nil },
                                               refresh: { _ in tokens("r2", expires: 3600) }, save: { saved.append($0); return true })
        #expect(out.refreshToken == "r2")
        #expect(saved.map(\.refreshToken) == ["r2"])
    }

    @Test func aFailedSaveIsTriedAgainAndTheNewPairStillUsed() async throws {
        var tries = 0
        let out = try await TokenRefresh.fresh(tokens("r1", expires: 60), now: now, reread: { nil },
                                               refresh: { _ in tokens("r2", expires: 3600) }, save: { _ in tries += 1; return false })
        #expect(tries == 2)
        #expect(out.refreshToken == "r2")
    }

    @Test func turnedDownAfterAnotherProcessRotatedThemUsesTheirs() async throws {
        let theirs = tokens("r2", expires: 3600)
        let out = try await TokenRefresh.fresh(tokens("r1", expires: 60), now: now, reread: { theirs },
                                               refresh: { _ in throw gone }, save: { _ in true })
        #expect(out == theirs)
    }

    @Test func turnedDownWithNothingNewerMeansSignIn() async {
        let mine = tokens("r1", expires: 60)
        await #expect(throws: OAuthError.self) {
            try await TokenRefresh.fresh(mine, now: now, reread: { mine }, refresh: { _ in throw gone }, save: { _ in true })
        }
        await #expect(throws: OAuthError.self) {
            try await TokenRefresh.fresh(mine, now: now, reread: { nil }, refresh: { _ in throw gone }, save: { _ in true })
        }
    }

    @Test func aServerErrorIsNotASignOut() async {
        // A 5xx is passed on as it is, without looking for someone else's tokens.
        await #expect(throws: OAuthError(code: "http_503", message: "down")) {
            try await TokenRefresh.fresh(tokens("r1", expires: 60), now: now, reread: { Issue.record("reread"); return nil },
                                         refresh: { _ in throw OAuthError(code: "http_503", message: "down") }, save: { _ in true })
        }
    }
}
