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
// Two methods. That is the entire slice the transport uses (ADR-0001: prefer a
// narrow read seam over the whole store).

import Foundation

@MainActor
protocol AccessTokenProviding {
    /// Throws when no usable session exists. Refreshing the session is a side
    /// effect of asking, which is what makes the one-shot 401 retry work.
    func validAccessToken() async throws -> String
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
}
