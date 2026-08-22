// What a reader is allowed to see when something fails.
//
// `Error.localizedDescription` is only trustworthy for errors we wrote.
// `APIError` localizes every case; a Supabase SDK error, a Foundation error, a
// StoreKit error do not — they hand back English, and in the SDK case that
// English is whatever the remote service put in its JSON `message` field.
//
// On 2026-08-19 the Supabase project was egress-restricted and every request
// came back
//
//     {"message":"Service for this project is restricted due to the following
//      violations: exceed_cached_egress_quota, exceed_egress_quota. The project
//      owner must upgrade their plan or remove spend caps to restore service."}
//
// which a `catch { self.error = error.localizedDescription }` rendered verbatim,
// in English, to a zh-Hant reader, on the onboarding screen — the first thing a
// new user saw. A billing message meant for the developer, shown to the customer.
//
// So the rule lives here rather than at each `catch`: a screen asks what to say,
// and cannot accidentally say something else.

import Foundation
import OSLog

private let userFacingErrorLog = Logger(subsystem: "app.tuji.ios", category: "user-facing-error")

/// User-facing copy for any error, ours or not.
///
/// Errors we own pass through with the copy they already carry. Anything else is
/// logged in full and replaced with generic text — losing the detail on screen is
/// the point; it stays in the log, where it is actually useful.
///
/// `fallback` lets a screen supply copy that fits its own context ("這張圖片沒能
/// 上傳") instead of the generic line.
func tujiUserMessage(for error: Error, fallback: String? = nil) -> String {
    let generic = { fallback ?? tujiLocalized("操作沒有完成，請稍後再試") }

    if error is CancellationError { return generic() }

    if let apiError = error as? APIError {
        // Every APIError case is localized, and `.server` no longer forwards the
        // body. The raw text goes to the log instead.
        userFacingErrorLog.error("api: \(apiError.diagnostic, privacy: .public)")
        return apiError.errorDescription ?? generic()
    }

    // A URLError can reach a screen without passing through APIClient — an image
    // load, an SDK call. Give it the same plain-language treatment.
    if let urlError = error as? URLError {
        if urlError.code == .cancelled { return generic() }
        userFacingErrorLog.error("url \(urlError.code.rawValue, privacy: .public)")
        return APIError.transport(urlError).errorDescription ?? generic()
    }

    userFacingErrorLog.error("foreign: \(String(describing: error), privacy: .public)")
    return generic()
}
