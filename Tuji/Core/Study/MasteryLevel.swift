// Client-side 5-level mastery tier, derived purely from the 0–100 score the
// server keeps in user_words.mastery. The backend lib/mastery.ts has its own
// 4-level scheme for the web; iOS owns this independent 5-level display so the
// tier names (未學 → 知道 → 熟悉 → 熟練 → 精通) stay app-specific. We ignore the
// `level` object the answer endpoint returns and always re-derive here.
//
// Progressive thresholds (tuned to the EMA: one correct answer lands ~21–30,
// so 精通 genuinely takes many reviews and stays prestigious):
//   未學  no record / 0
//   知道  1–34
//   熟悉  35–59
//   熟練  60–79
//   精通  80–100

import SwiftUI

enum MasteryLevel: Int, CaseIterable {
    case notLearned
    case know
    case familiar
    case proficient
    case expert

    /// Map a 0–100 score to a tier. `nil` (no user_words row) or 0 → 未學.
    static func from(score: Int?) -> MasteryLevel {
        guard let s = score, s > 0 else { return .notLearned }
        switch s {
        case 80...: return .expert
        case 60...: return .proficient
        case 35...: return .familiar
        default: return .know // 1...34
        }
    }

    /// Localized tier name as a `LocalizedStringKey` so `Text(level.name)`
    /// resolves it against the SwiftUI environment locale (driven by uiLang) and
    /// live-updates when the user switches interface language.
    var name: LocalizedStringKey {
        switch self {
        case .notLearned: "未學"
        case .know: "知道"
        case .familiar: "熟悉"
        case .proficient: "熟練"
        case .expert: "精通"
        }
    }

    /// Ground colour for the tier. This is the one place a colour is allowed to
    /// act as a *category* rather than a meaning — mastery is the most important
    /// data in the app, so it gets a ladder of its own.
    ///
    /// The ladder climbs through teal because mastery **is** 積累. The old ladder
    /// ran grey → rose → amber → sky → emerald, which borrowed the error colour
    /// for 知道 and the "now" colour for 熟悉 — two tiers of ordinary progress
    /// wearing signals that mean something else entirely.
    var background: Color {
        switch self {
        case .notLearned: .tujiPaper3
        case .know: .tujiAccumulationSoft
        case .familiar: .tujiAccumulation
        case .proficient: .tujiAccumulationDeep
        case .expert: .tujiInk
        }
    }

    /// Text/mark colour to sit on `background`.
    ///
    /// 全精通 is the only 墨底 + 瞳字 pairing in the whole system. That
    /// combination appears nowhere else, which is what gives it weight — it does
    /// not need a purple of its own.
    var foreground: Color {
        switch self {
        case .notLearned: .tujiInk3
        case .know: .tujiAccumulationDeep
        case .familiar, .proficient: .tujiPaper
        case .expert: .tujiCurrent
        }
    }

    /// How many of the five scale segments are filled. Drives `MasteryBadge`.
    var filledSegments: Int {
        switch self {
        case .notLearned: 0
        case .know: 1
        case .familiar: 2
        case .proficient: 3
        case .expert: 5
        }
    }
}
