// Characterisation for the auth state machine.
//
// `AuthService` is reached from 43 sites and had **no tests at all**:
// `private init()` plus a Supabase client that `fatalError`s on a missing plist
// key make it unconstructible in a test process. So every rule below — each one
// a fact a caller must know, none of them stated by a type — was verified by
// nobody. These assert current behaviour, deliberately: the point is a net
// under the state machine, not a change to it.

import Foundation
import Testing
@testable import Tuji

struct AuthSessionTests {
    private func user(_ nickname: String? = nil) -> SessionUser {
        SessionUser(
            id: UUID(uuidString: "00000000-0000-0000-0000-0000000000A1")!,
            email: "a@example.com",
            username: "TJ00000001",
            nickname: nickname,
            avatar: nil
        )
    }

    private func otherUser() -> SessionUser {
        SessionUser(
            id: UUID(uuidString: "00000000-0000-0000-0000-0000000000B2")!,
            email: "b@example.com",
            username: "TJ00000002",
            nickname: nil,
            avatar: nil
        )
    }

    // MARK: - Launch

    @Test
    func aFreshSessionStartsChecking() {
        #expect(AuthSession().state == .checking)
        #expect(!AuthSession().cameFromGuest)
    }

    /// The app's whole offline-launch behaviour: a refresh that fails while a
    /// session is still cached keeps the user signed in. Bouncing an
    /// authenticated user to Welcome over a flat network is worse than carrying
    /// a stale token to the next refresh.
    @Test
    func anUnreachableRefreshKeepsTheCachedSession() {
        var s = AuthSession()
        s.failedRefresh(.unreachable, cached: self.user())
        #expect(s.state == .signedIn(self.user()))
    }

    /// "No session at all" is the one failure that really means signed out —
    /// even if something is cached.
    @Test
    func aMissingSessionSignsOutRegardless() {
        var s = AuthSession()
        s.failedRefresh(.noSession, cached: self.user())
        #expect(s.state == .signedOut)
    }

    @Test
    func anUnreachableRefreshWithNothingCachedSignsOut() {
        var s = AuthSession()
        s.failedRefresh(.unreachable, cached: nil)
        #expect(s.state == .signedOut)
    }

    // MARK: - Guest

    @Test
    func guestModeIsEnteredOnlyFromSignedOut() {
        var s = AuthSession()
        s.enterGuest() // from .checking — silently does nothing
        #expect(s.state == .checking)

        s.signedOut()
        s.enterGuest()
        #expect(s.state == .guest)
    }

    @Test
    func guestModeIsLeftOnlyFromGuest() {
        var s = AuthSession()
        s.signedIn(self.user())
        s.exitGuest() // signed in — nothing happens
        #expect(s.state == .signedIn(self.user()))
    }

    /// `cameFromGuest` is what stops Welcome being an exit-less dead end for
    /// someone who tapped 登入 by accident. Only *leaving* guest mode sets it.
    @Test
    func onlyLeavingGuestModeMarksCameFromGuest() {
        var s = AuthSession()
        s.signedOut()
        s.enterGuest()
        #expect(!s.cameFromGuest)

        s.exitGuest()
        #expect(s.cameFromGuest)
    }

    @Test
    func signingOutClearsCameFromGuest() {
        var s = AuthSession()
        s.signedOut()
        s.enterGuest()
        s.exitGuest()
        #expect(s.cameFromGuest)

        s.signedOut()
        #expect(!s.cameFromGuest)
        #expect(s.state == .signedOut)
    }

    // MARK: - Profile mirror

    @Test
    func theNicknameMirrorAppliesWhileSignedIn() {
        var s = AuthSession()
        s.signedIn(self.user())
        s.applyNickname("阿貓")
        #expect(s.signedInUser?.nickname == "阿貓")
    }

    /// A profile edit that lands after a sign-out must not resurrect the
    /// session.
    @Test
    func theProfileMirrorIsIgnoredWhenNotSignedIn() {
        var s = AuthSession()
        s.signedOut()
        s.applyNickname("阿貓")
        s.applyProfile(nickname: "阿貓", avatar: "a.png")
        #expect(s.state == .signedOut)
    }

    /// The hydrate request runs off the launch-critical path, so the account
    /// may have switched while it was in flight. Publishing then would show one
    /// account's identity over another's session.
    @Test
    func aReconcileForAnotherAccountIsDropped() {
        var s = AuthSession()
        s.signedIn(self.user())
        s.reconcile(self.otherUser(), ifStillSignedInAs: self.otherUser().id)
        #expect(s.signedInUser?.id == self.user().id)
    }

    @Test
    func aReconcileForTheSameAccountIsPublished() {
        var s = AuthSession()
        s.signedIn(self.user())
        s.reconcile(self.user("阿貓"), ifStillSignedInAs: self.user().id)
        #expect(s.signedInUser?.nickname == "阿貓")
    }

    @Test
    func aReconcileAfterSignOutIsDropped() {
        var s = AuthSession()
        s.signedIn(self.user())
        s.signedOut()
        s.reconcile(self.user("阿貓"), ifStillSignedInAs: self.user().id)
        #expect(s.state == .signedOut)
    }
}
