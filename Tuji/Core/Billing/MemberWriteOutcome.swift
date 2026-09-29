// How a write to a member feature (詞表, 筆記) came back, in the only terms a
// screen acts on. Access itself is `MemberAccess`; this is what the server said
// about one write.

import Foundation

/// How a write to a member feature (詞表, 筆記) came back, in the only terms a
/// screen acts on.
enum MemberWriteOutcome: Equatable {
    case done
    /// 402: buying something would allow it — show the paywall.
    case needsUpgrade
    /// 429: at the top tier's ceiling — only removing something helps.
    case atLimit
    /// The list is gone (deleted on another device).
    case missing
    case failed(String)

    static func from(_ error: Error) -> MemberWriteOutcome {
        switch error as? APIError {
        case .paymentRequired: .needsUpgrade
        case .rateLimited, .atCapacity: .atLimit
        case .notFound: .missing
        default: .failed(tujiUserMessage(for: error))
        }
    }
}
