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

    /// Tier accent. Grey for 未學, then the backend's rose→amber→sky→emerald
    /// progression mapped onto Tuji's palette.
    var color: Color {
        switch self {
        case .notLearned: .tujiInk4
        case .know: .tujiCoral
        case .familiar: .tujiYellow
        case .proficient: .tujiTeal
        case .expert: .tujiGreen
        }
    }

    /// De-emphasized colour for the 圖鑑 tile badge: only 精通 stands out in
    /// green, every other tier is neutral grey. (The detail page keeps the
    /// full-colour `color`.)
    var tileBadgeColor: Color {
        self == .expert ? .tujiGreen : .tujiInk3
    }
}
