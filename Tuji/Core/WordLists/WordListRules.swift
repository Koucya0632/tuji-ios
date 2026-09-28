// 個人詞表 — what a screen does with what the server said.
//
// Pure: every branch here is a test, not a screenshot. The server owns the
// rules (tuji-web lib/word-lists/policy.ts); these only decide how the app
// presents its answers.

import Foundation

/// How an entry point to 詞表 shows up.
enum WordListEntry: Equatable {
    /// Membership policy v1, or not known yet: no entry point at all
    /// (decided 2026-09-28 — new member benefits are invisible under v1).
    case hidden
    /// A non-member: a lock, and tapping it opens the paywall.
    case locked
    case open
}

enum WordListRules {
    /// The 我 row. A non-member who still has lists (a refund) can open them:
    /// they keep what they made, read-only.
    static func browseEntry(available: Bool?, tier: String?, listCount: Int) -> WordListEntry {
        guard available == true else { return .hidden }
        if tier == "free", listCount == 0 { return .locked }
        return .open
    }

    /// The word page's 加入詞表. Adding is the member feature, so a non-member
    /// meets the lock here even when they have lists.
    static func addEntry(available: Bool?, tier: String?) -> WordListEntry {
        guard available == true else { return .hidden }
        return tier == "free" ? .locked : .open
    }
}

/// How a write came back, in the only terms a screen acts on.
enum WordListWriteOutcome: Equatable {
    case done
    /// 402: buying something would allow it — show the paywall.
    case needsUpgrade
    /// 429: at the top tier's ceiling — only removing something helps.
    case atLimit
    /// The list is gone (deleted on another device).
    case missing
    case failed(String)

    static func from(_ error: Error) -> WordListWriteOutcome {
        switch error as? APIError {
        case .paymentRequired: .needsUpgrade
        case .rateLimited, .atCapacity: .atLimit
        case .notFound: .missing
        default: .failed(tujiUserMessage(for: error))
        }
    }
}
