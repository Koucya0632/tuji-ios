// A theme, drawn as a tile: name, word count, and how far through it you are.
//
// Lives here rather than inside TodayView because two screens draw it now —
// the 今天 theme strip (your chosen study themes) and 主題, the browse index
// that replaced the 圖鑑 theme chip row. The completion rule is the interesting
// part and it used to be a private method on TodayView, so the second caller
// would have had to copy it; `ThemeStatus.of` is that rule, extracted as a pure
// function so both screens and a test can ask the same question.

import SwiftUI

/// Theme-tile completion marker.
enum ThemeStatus {
    case none
    case completed
    case mastered

    /// `.mastered` (全精通) wins over `.completed` (完成) since all-精通 already
    /// implies every word was seen. Guests have no mastery / progress data, so
    /// this stays `.none` for them by way of empty inputs.
    ///
    /// - Parameters:
    ///   - words: every word in the theme.
    ///   - masteryScore: 0–100 for a word, or nil if never studied.
    ///   - progress: the server's per-theme seen/total rows.
    static func of(
        words: [CardWord],
        masteryScore: (String) -> Int?,
        progress: [CategoryProgress],
        categoryId: String
    )
        -> ThemeStatus
    {
        guard !words.isEmpty else { return .none }
        // 全精通: every word in the theme sits at the top tier (精通, score ≥ 80).
        // An unstudied word reads as 未學, so all-精通 also means all-seen.
        let allMastered = words.allSatisfy {
            MasteryLevel.from(score: masteryScore($0.id)) == .expert
        }
        if allMastered { return .mastered }
        // 完成: the server says every published card in the theme has been
        // studied at least once (seen == total), even if some later decayed
        // below 精通.
        if let row = progress.first(where: { $0.category == categoryId }),
           row.total > 0, row.seen == row.total
        {
            return .completed
        }
        return .none
    }
}

struct CategoryTile: View {
    let category: TujiCategory
    let wordCount: Int
    var status: ThemeStatus = .none

    private var accent: Color {
        switch self.status {
        case .mastered: .tujiInk
        case .completed: .tujiAccumulation
        case .none: .tujiPaper3
        }
    }

    var body: some View {
        VStack(spacing: 3) {
            Text(self.category.nameZh)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.tujiInk)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            Text("\(self.wordCount) 字")
                .font(.tujiLabel)
                .foregroundStyle(.tujiInk3)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, Space.s2)
        .padding(.vertical, Space.s3)
        .background(.tujiPaper, in: .rect(cornerRadius: Radius.r0))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.r0)
                .stroke(self.accent, lineWidth: self.status == .none ? 1 : 1.5)
        )
        .overlay(alignment: .topTrailing) {
            ThemeStatusBadge(status: self.status)
                .padding(5)
        }
    }
}

/// Corner marker on a theme tile: 完成 once every word has been seen,
/// 全精通 once every word reaches 精通. Renders nothing for `.none`.
struct ThemeStatusBadge: View {
    let status: ThemeStatus

    var body: some View {
        switch self.status {
        case .none:
            EmptyView()
        case .completed:
            self.pill(text: "完成", icon: "checkmark.seal.fill", tint: .tujiAccumulation)
        case .mastered:
            self.pill(text: "全精通", icon: "crown.fill", tint: .tujiInk)
        }
    }

    private func pill(text: LocalizedStringKey, icon: String, tint: Color) -> some View {
        HStack(spacing: 2) {
            Image(systemName: icon)
                .font(.system(size: 8, weight: .semibold))
            Text(text)
                .font(.system(size: 9, weight: .semibold))
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 5)
        .padding(.vertical, 2)
        .background(.tujiPaper, in: .rect(cornerRadius: Radius.r0))
        .overlay(Rectangle().stroke(tint.opacity(0.4), lineWidth: 1))
        .shadow(color: .black.opacity(0.1), radius: 1.5, y: 1)
    }
}
