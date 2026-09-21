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

extension ThemeStatus {
    /// The frame a tile in this state wears. Two tiles draw it now — the plain
    /// one below and `CategoryCoverTile` — so the colour and the weight are the
    /// status's own answer rather than each tile's.
    var accent: Color {
        switch self {
        case .mastered: .tujiInk
        case .completed: .tujiAccumulation
        case .none: .tujiPaper3
        }
    }

    /// A marked tile's frame is half a point heavier, which is the whole of the
    /// difference at rest — see Border.swift on why it is not a colour step.
    var frameWidth: CGFloat {
        self == .none ? 1 : 1.5
    }
}

struct CategoryTile: View {
    let category: TujiCategory
    let wordCount: Int
    var status: ThemeStatus = .none

    var body: some View {
        VStack(spacing: 3) {
            Text(self.category.nameZh)
                .font(.tujiBodySm(.strong))
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
                .stroke(self.status.accent, lineWidth: self.status.frameWidth)
        )
        .overlay(alignment: .topTrailing) {
            ThemeStatusBadge(status: self.status)
                .padding(5)
        }
    }
}

/// The same theme, with its picture: 圖鑑·官方 is a shelf of themes rather than
/// a flat run of 757 words, and a shelf that shows nothing but names is a list.
///
/// Separate from `CategoryTile` rather than a flag on it because 今天's strip
/// wants the opposite thing — two rows of themes in the height this tile gives
/// one — and a tile that draws a cover only sometimes would owe both callers an
/// explanation. What they share (the frame, the badge, the picture rule) they
/// share by name: `ThemeStatus.accent`, `ThemeStatusBadge`, `CategoryArtwork`.
struct CategoryCoverTile: View {
    let category: TujiCategory
    let wordCount: Int
    var status: ThemeStatus = .none

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // The *container* owns the shape, the way WordTile's square does:
            // a 16:9 box measured from the cell, with the artwork filling it
            // from inside. Asking the picture for the aspect ratio instead lets
            // a 1280-wide cover negotiate its own size and push the grid apart.
            // 16:9 because that is the crop 主題's hero shows, so a theme looks
            // like itself on both screens.
            Color.tujiPaper2
                .aspectRatio(16.0 / 9.0, contentMode: .fit)
                .overlay {
                    CategoryArtwork(category: self.category)
                }
                .clipped()

            VStack(alignment: .leading, spacing: 3) {
                Text(self.category.nameZh)
                    .font(.tujiBodySm(.strong))
                    .foregroundStyle(.tujiInk)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                Text("\(self.wordCount) 字")
                    .font(.tujiLabel)
                    .foregroundStyle(.tujiInk3)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Space.s2)
            .padding(.vertical, Space.s3)
        }
        .background(.tujiPaper, in: .rect(cornerRadius: Radius.r0))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.r0)
                .stroke(self.status.accent, lineWidth: self.status.frameWidth)
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
                .font(.tujiIcon(8, weight: .semibold))
            Text(text)
                .font(.tujiIcon(9, weight: .semibold))
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 5)
        .padding(.vertical, 2)
        .background(.tujiPaper, in: .rect(cornerRadius: Radius.r0))
        .overlay(Rectangle().stroke(tint.opacity(0.4), lineWidth: 1))
        .shadow(color: .black.opacity(0.1), radius: 1.5, y: 1)
    }
}
