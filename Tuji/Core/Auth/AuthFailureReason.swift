// Why a sign-in attempt failed, as a decision rather than a sentence.
//
// `AuthService.friendly(_:)` matched seven server messages inline and nothing
// verified any of them: `AuthService` has a `private init` and a
// `SupabaseProvider.client` that `fatalError`s without configuration, so the
// whole class is unconstructible in a test process. Every branch in that
// function was therefore a claim nobody had checked.
//
// One of them was missing, and the omission was user-visible: an account whose
// email has never been confirmed gets `email_not_confirmed` from the server,
// fell through to the generic arm, and was told 「登入沒有成功，請稍後再試」 —
// advice that can never work, because the fix is an unopened inbox. Found by
// signing up for real on Android, whose port of this function had inherited the
// same six branches.
//
// Only the *matching* moved here, not the whole function. `friendly(_:)`'s
// fallback arm still routes through `tujiUserMessage(for:fallback:)`, which
// does real work — it recognises `APIError` and `URLError` and produces the
// offline wording. A "classifier" that swallowed that would trade one wrong
// sentence for another.
//
// Tests assert the *reason*, never the sentence: CI runs in English and a
// developer's machine runs in 繁體中文.

import Foundation

/// A server message this app knows how to explain.
nonisolated enum AuthFailureReason: CaseIterable {
    case invalidCredentials
    case emailNotConfirmed
    case emailAlreadyRegistered
    case rateLimited
    case providerNotEnabled
    case passwordTooShort
    case invalidEmail

    /// Classifies by message because it is the only signal Supabase gives for
    /// these — the HTTP status is 400 for nearly all of them.
    ///
    /// `nil` means "not one of ours", which is not the same as "no error": the
    /// caller still has a fallback, and it is a better fallback than any
    /// sentence this type could invent.
    init?(serverMessage message: String) {
        let has = { (needle: String) in message.localizedCaseInsensitiveContains(needle) }
        switch true {
        // The machine-readable code first. Supabase is free to reword the prose
        // in a release; the code is part of its API.
        case has("email_not_confirmed"), has("email not confirmed"):
            self = .emailNotConfirmed
        case has("invalid login credentials"):
            self = .invalidCredentials
        case has("user already registered"):
            self = .emailAlreadyRegistered
        case has("rate limit"):
            self = .rateLimited
        case has("provider") where has("not enabled"):
            self = .providerNotEnabled
        case has("password should be"):
            self = .passwordTooShort
        case has("email address") where has("invalid"):
            self = .invalidEmail
        default:
            return nil
        }
    }

    /// What to tell the user. One sentence per reason; the server's own English
    /// never reaches a screen.
    var message: String {
        switch self {
        case .invalidCredentials: tujiLocalized("Email 或密碼錯誤")
        case .emailNotConfirmed: tujiLocalized("這個 Email 還沒確認。收信點一下連結，就能登入了")
        case .emailAlreadyRegistered: tujiLocalized("此 Email 已註冊，請改用登入")
        case .rateLimited: tujiLocalized("嘗試太頻繁，請稍後再試")
        case .providerNotEnabled: tujiLocalized("Apple 登入尚未啟用，請稍後再試")
        case .passwordTooShort: tujiLocalized("密碼太短（至少 8 字）")
        case .invalidEmail: tujiLocalized("Email 格式或網域不被接受")
        }
    }
}
