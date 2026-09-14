// What the HTTP client needs from authentication, and nothing else.
//
// `APIClient` took a concrete `AuthService`, whose `init` is `private` and
// whose only instance reaches `SupabaseProvider.client` — which `fatalError`s
// when `TUJI_SUPABASE_URL` / `TUJI_SUPABASE_ANON_KEY` are missing from
// `Info.plist`, and otherwise hits the Keychain and the network for a session.
//
// That single dependency is what made the whole transport untestable. A
// `URLProtocol` stub was already possible (`urlSession` is injectable), but it
// could only ever reach the 11 public endpoints: every authenticated path —
// which is 50 of 61 endpoints, plus the 401 retry, plus the multipart upload —
// went through `validAccessToken()` first and could not be stood up.
//
// Three members. That is the entire slice the transport uses (ADR-0001: prefer
// a narrow read seam over the whole store).

import Foundation

@MainActor
protocol AccessTokenProviding {
    /// Throws when no usable session exists. Refreshes only when *this device*
    /// believes the token has expired.
    func validAccessToken() async throws -> String
    /// A token to replace `rejected`, which the server has just answered with a
    /// 401 — so the device's belief about when it expires is not to be trusted.
    ///
    /// `validAccessToken()` alone cannot serve the 401 retry. supabase-swift
    /// judges expiry by comparing the server's `expires_at` with this device's
    /// clock, and a clock running behind makes an expired token look good: the
    /// retry re-sent the value the server had just refused, and every
    /// signed-in request failed for as long as the clock stayed behind.
    ///
    /// Returns the current token without refreshing when it is already not
    /// `rejected` — see `TokenReplacement`. `rejected` is nil when the refused
    /// request went out without a token.
    func refreshedAccessToken(rejected: String?) async throws -> String
    /// Whether to *attempt* a token on an optional-auth endpoint. Distinct from
    /// "a token is available": an optional-auth request must stay usable for
    /// signed-out guests, so this only decides whether to try.
    var isSignedIn: Bool { get }
}

extension AuthService: AccessTokenProviding {
    var isSignedIn: Bool {
        if case .signedIn = self.state { return true }
        return false
    }

    func refreshedAccessToken(rejected: String?) async throws -> String {
        let current = try? await self.validAccessToken()
        if let current, TokenReplacement.decide(current: current, rejected: rejected) == .useCurrent {
            return current
        }
        return try await self.refreshSession()
    }
}
