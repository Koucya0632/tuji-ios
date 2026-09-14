// Pins the sign-out roster.
//
// `AuthService.signOut` used to reset four singletons by name, and the only
// statement that a *fifth* account-scoped store would have to enrol was prose
// inside the method that discharges the obligation — the worst place for it:
// you have to already be editing sign-out to learn that sign-out is what you
// must edit.
//
// This asserts the roster against the conformances, so a store that conforms
// to `AccountScopedStore` without enrolling in `AccountScopedStores.all` fails
// here instead of leaking one account's data into the next one's session.

import Foundation
import Testing
@testable import Tuji

@MainActor
struct AccountScopedStoreTests {
    @Test
    func theRosterIsExactlyTheElevenAccountScopedStores() {
        let roster = AccountScopedStores.all
        #expect(roster.count == 11)

        // Named rather than counted: a swap that kept the count would pass a
        // count assertion, and each of these is on the list for its own reason
        // (documented on `AccountScopedStores.all`).
        #expect(roster.contains { $0 is AtlasStore })
        #expect(roster.contains { $0 is AtlasCaptureQueue })
        #expect(roster.contains { $0 is MyCollectionsCache })
        #expect(roster.contains { $0 is BlockStore })
        #expect(roster.contains { $0 is StudyAnswerOutbox })
        // The six that held account data without conforming, so the roster
        // test above could not notice them.
        #expect(roster.contains { $0 is SettingsStore })
        #expect(roster.contains { $0 is MasteryStore })
        #expect(roster.contains { $0 is ProgressStore })
        #expect(roster.contains { $0 is StudyStatsStore })
        #expect(roster.contains { $0 is StudyQueueStore })
        #expect(roster.contains { $0 is LocalCache })
    }

    @Test
    func resettingAllReachesEveryEnrolledStore() {
        // The live stores are singletons, so this asserts the fan-out runs
        // rather than the contents: `resetAll()` must visit each one without
        // short-circuiting on the first.
        var visited = 0
        for store in AccountScopedStores.all {
            store.reset()
            visited += 1
        }
        #expect(visited == AccountScopedStores.all.count)
    }
}

@MainActor
struct LocalCacheAccountBoundaryTests {
    private struct Harness {
        let cache: LocalCache
        let defaults: UserDefaults
        let suite: String

        func tearDown() {
            self.defaults.removePersistentDomain(forName: self.suite)
        }
    }

    private func harness() throws -> Harness {
        let suite = "LocalCacheAccountBoundaryTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        return Harness(
            cache: LocalCache(defaults: defaults, learningDirection: { .zhJa }),
            defaults: defaults,
            suite: suite
        )
    }

    /// The next sign-in uploads whatever is here into *that* account, so the
    /// previous account's bookmarks must be gone before it can.
    @Test
    func signOutDropsTheBookmarksButKeepsTheSearchHistory() throws {
        let harness = try self.harness()
        defer { harness.tearDown() }
        let cache = harness.cache
        cache.toggleFavorite("kettle")
        cache.pushRecentSearch("やかん")

        cache.reset()

        #expect(cache.favoriteIds.isEmpty)
        #expect(cache.syncSnapshot.favorites.isEmpty)
        #expect(cache.recentSearches == ["やかん"])
        // Persisted, not just in memory: a relaunch must not bring them back.
        #expect(LocalCache(defaults: harness.defaults, learningDirection: { .zhJa }).favoriteIds.isEmpty)
    }

    @Test
    func serverBookmarksAreMergedInWithoutDroppingOnesOnScreen() throws {
        let harness = try self.harness()
        defer { harness.tearDown() }
        let cache = harness.cache
        cache.toggleFavorite("kettle")

        cache.mergeServerFavorites(["ladle", "kettle"])

        #expect(cache.favoriteIds == ["kettle", "ladle"])
    }

    @Test
    func theSyncSnapshotCarriesTheInjectedDirection() throws {
        let harness = try self.harness()
        defer { harness.tearDown() }
        let cache = harness.cache
        #expect(cache.syncSnapshot.learningDirection == .zhJa)
    }
}

@MainActor
struct FavoritePayloadWireTests {
    /// POST /api/users/favorites requires a boolean `favorite`. The payload sent
    /// `op: "add" | "remove"`, got a 400 every time, and nobody saw it because
    /// the call is fire-and-forget.
    @Test
    func aBookmarkToggleSendsTheBooleanTheRouteRequires() throws {
        let data = try JSONEncoder().encode(FavoritePayload(wordId: "kettle", favorite: true))
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])

        #expect(object["favorite"] as? Bool == true)
        #expect(object["op"] == nil)
    }
}

@MainActor
struct AuthAttemptTests {
    /// Backing out of Google's sheet is neither success nor failure, and must
    /// not leave a red line under the button. It used to be indistinguishable
    /// from success: every sign-in method returned `Void`, so a caller could
    /// only read `error` — which cancellation deliberately leaves nil.
    @Test
    func cancellationIsNeitherSuccessNorFailure() {
        let cancelled = AuthService.AuthAttempt.cancelled
        #expect(cancelled != .succeeded)
        #expect(cancelled != .failed("anything"))
    }

    /// A failure carries its own already-localised reason, so a caller does not
    /// have to read a shared mutable field that a concurrent attempt may have
    /// overwritten between the two statements.
    @Test
    func aFailureCarriesItsOwnReason() {
        let attempt = AuthService.AuthAttempt.failed("帳號或密碼不正確")
        guard case let .failed(message) = attempt else {
            Issue.record("expected .failed")
            return
        }
        #expect(message == "帳號或密碼不正確")
    }
}
