// The auth state machine, minus Supabase.
//
// `AuthService` is 371 lines reached from 43 sites and has no characterisation
// at all: `private init()` plus a `SupabaseProvider.client` that `fatalError`s
// on a missing plist key make it unconstructible in a test process. So the
// rules below — every one of them a fact a caller must know and none of them
// stated by a type — were verified by nobody:
//
//   • `enterGuestMode` only works from `.signedOut` and `exitGuestMode` only
//     from `.guest`. From anywhere else they are **silent no-ops**: no throw,
//     no signal, nothing happens.
//   • `cameFromGuest` is what stops Welcome being an exit-less dead end for
//     someone who tapped 登入 by accident. It is set by *leaving* guest mode
//     and cleared by signing out — a distinction with no test.
//   • A failed session refresh does **not** mean signed out. If a session is
//     still cached and the error is anything other than "no session at all",
//     the likely cause is a flat network, and bouncing an authenticated user
//     to Welcome over a transient hiccup is worse than carrying a stale token
//     to the next refresh. That is the app's whole offline-launch behaviour.
//   • `applyNickname` / `applyProfile` are optimistic mirrors that only apply
//     while signed in — a profile edit that lands after a sign-out must not
//     resurrect the session.
//
// None of that needs a network client, so none of it has to live behind one.
// The Supabase glue stays in `AuthService`; this is the part a test can hold.

import Foundation

/// Where the account stands. Nested in `AuthService` as `State` for the 43 call
/// sites that already spell it that way.
enum AuthState: Equatable {
    case checking
    case signedOut
    /// Browsing without an account.
    case guest
    case signedIn(SessionUser)
}

/// What a failed `supabase.auth.session` refresh resolves to.
enum SessionRefreshFailure: Equatable {
    /// There was never a session — a genuinely signed-out launch.
    case noSession
    /// A session is cached but could not be refreshed. Most likely offline.
    case unreachable
}

struct AuthSession: Equatable {
    private(set) var state: AuthState = .checking

    /// True when Welcome was reached by *leaving* guest mode rather than at
    /// first launch, so Welcome can offer a way back to browsing.
    private(set) var cameFromGuest = false

    var signedInUser: SessionUser? {
        guard case let .signedIn(user) = state else { return nil }
        return user
    }

    // MARK: - Launch

    mutating func restored(_ user: SessionUser) {
        self.state = .signedIn(user)
    }

    /// A refresh that threw. `.unreachable` keeps the cached session: see the
    /// offline rule at the top of this file.
    mutating func failedRefresh(_ failure: SessionRefreshFailure, cached: SessionUser?) {
        switch failure {
        case .unreachable where cached != nil:
            self.state = .signedIn(cached!)
        case .unreachable, .noSession:
            self.state = .signedOut
        }
    }

    // MARK: - Guest

    /// No-op unless signed out. Stated here because the type cannot say it.
    mutating func enterGuest() {
        guard case .signedOut = state else { return }
        self.state = .guest
        self.cameFromGuest = false
    }

    /// No-op unless in guest mode.
    mutating func exitGuest() {
        guard case .guest = state else { return }
        self.state = .signedOut
        self.cameFromGuest = true
    }

    // MARK: - Sign in / out

    mutating func signedIn(_ user: SessionUser) {
        self.state = .signedIn(user)
    }

    mutating func signedOut() {
        self.state = .signedOut
        self.cameFromGuest = false
    }

    // MARK: - Profile mirror

    /// Optimistic mirrors, applied only while signed in — an edit that lands
    /// after a sign-out must not resurrect the session.
    mutating func applyNickname(_ nickname: String?) {
        guard case let .signedIn(user) = state else { return }
        self.state = .signedIn(user.withNickname(nickname))
    }

    mutating func applyProfile(nickname: String?, avatar: String?) {
        guard case let .signedIn(user) = state else { return }
        self.state = .signedIn(user.withProfile(nickname: nickname, avatar: avatar))
    }

    /// Publish a reconciled profile only if the session is still the same
    /// account. The hydrate request runs off the launch-critical path, so the
    /// user may have signed out or switched while it was in flight.
    mutating func reconcile(_ user: SessionUser, ifStillSignedInAs id: UUID) {
        guard case let .signedIn(current) = state, current.id == id else { return }
        self.state = .signedIn(user)
    }
}
