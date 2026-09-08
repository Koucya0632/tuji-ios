// `AuthService.friendly(_:)` matched seven server messages inline, and nothing
// verified any of them: the class has a `private init` and a Supabase client
// that `fatalError`s without configuration, so it cannot be constructed in a
// test process at all. Every branch was an unchecked claim, and one of them was
// missing — see `emailNotConfirmed` below.
//
// Assertions are on the *reason*, never on the sentence: CI runs in English and
// a developer's machine runs in 繁體中文, so asserting copy is asserting which
// machine you happen to be on.

import Foundation
import Testing
@testable import Tuji

struct AuthFailureReasonTests {
    @Test
    func recognisesInvalidCredentials() {
        #expect(AuthFailureReason(serverMessage: "Invalid login credentials") == .invalidCredentials)
    }

    @Test
    func recognisesAnAlreadyRegisteredEmail() {
        #expect(AuthFailureReason(serverMessage: "User already registered") == .emailAlreadyRegistered)
    }

    @Test
    func recognisesRateLimiting() {
        #expect(AuthFailureReason(serverMessage: "Email rate limit exceeded") == .rateLimited)
    }

    @Test
    func recognisesADisabledProvider() {
        #expect(AuthFailureReason(serverMessage: "Provider apple is not enabled") == .providerNotEnabled)
    }

    @Test
    func recognisesAShortPassword() {
        #expect(AuthFailureReason(serverMessage: "Password should be at least 8 characters") == .passwordTooShort)
    }

    @Test
    func recognisesAnUnacceptableAddress() {
        #expect(AuthFailureReason(serverMessage: "Email address is invalid") == .invalidEmail)
    }

    /// The branch that was missing. An account whose email has never been
    /// confirmed used to fall through to the generic arm and be told
    /// 「登入沒有成功，請稍後再試」 — advice that can never work, because the
    /// fix is an unopened inbox. Found by signing up for real on 2026-09-08.
    @Test
    func recognisesAnUnconfirmedEmail() {
        #expect(AuthFailureReason(serverMessage: "Email not confirmed: email_not_confirmed") == .emailNotConfirmed)
        #expect(AuthFailureReason(serverMessage: "Email not confirmed") == .emailNotConfirmed)
        #expect(AuthFailureReason(serverMessage: "email_not_confirmed") == .emailNotConfirmed)
    }

    /// Both messages contain "email". The address case needs "email address"
    /// *and* "invalid" together, so the two cannot collide.
    @Test
    func doesNotMistakeAnUnconfirmedEmailForABadAddress() {
        #expect(AuthFailureReason(serverMessage: "Email address is invalid") == .invalidEmail)
        #expect(AuthFailureReason(serverMessage: "Email not confirmed") == .emailNotConfirmed)
    }

    @Test
    func ignoresTheServersCapitalisation() {
        #expect(AuthFailureReason(serverMessage: "INVALID LOGIN CREDENTIALS") == .invalidCredentials)
        #expect(AuthFailureReason(serverMessage: "invalid login credentials") == .invalidCredentials)
    }

    /// The real 2026-08 outage string. It reached the sign-in screen verbatim
    /// once, because the fallback arm used to return the server's own message.
    /// Returning nil is what routes it to `tujiUserMessage`, which says
    /// something addressed to the reader instead.
    @Test
    func doesNotClaimToUnderstandADeveloperFacingOutageNotice() {
        let outage = """
        Service for this project is restricted due to the following violations: \
        exceed_cached_egress_quota. Please check your usage.
        """
        #expect(AuthFailureReason(serverMessage: outage) == nil)
    }

    @Test
    func doesNotBlameTheProviderForEveryMessageMentioningOne() {
        // "not enabled" is the other half of that decision.
        #expect(AuthFailureReason(serverMessage: "Provider returned an unexpected response") == nil)
    }

    /// Every reason has to be able to say something. A case added without copy
    /// would otherwise surface as an empty red line under the button.
    @Test
    func everyReasonHasAMessage() {
        for reason in AuthFailureReason.allCases {
            #expect(!reason.message.isEmpty)
        }
    }
}
