import Foundation

/// Narrow role for reading the signed-in user's own profile (see CONTEXT.md →
/// architecture / role seams). `LiveUserRepository` already implements it, so it
/// conforms for free.
///
/// The author profile needs this for exactly one case: its own page before the
/// user has published anything. `/api/atlas/public/authors/{uid}` 404s then —
/// deliberately, because that endpoint must not confirm whether a handle exists
/// — so the identity has to come from an authenticated route instead. This one
/// reads `profiles` directly, which is also why it is the authority for the UID.
@MainActor
protocol SelfProfileReading {
    func loadMe() async throws -> UserMeResponse
}

extension LiveUserRepository: SelfProfileReading {}
