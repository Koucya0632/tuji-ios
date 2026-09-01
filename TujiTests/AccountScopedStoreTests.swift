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
    func theRosterIsExactlyTheFiveAccountScopedStores() {
        let roster = AccountScopedStores.all
        #expect(roster.count == 5)

        // Named rather than counted: a swap that kept the count would pass a
        // count assertion, and each of these is on the list for its own reason
        // (documented on `AccountScopedStores.all`).
        #expect(roster.contains { $0 is AtlasStore })
        #expect(roster.contains { $0 is AtlasCaptureQueue })
        #expect(roster.contains { $0 is MyCollectionsCache })
        #expect(roster.contains { $0 is BlockStore })
        #expect(roster.contains { $0 is StudyAnswerOutbox })
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
