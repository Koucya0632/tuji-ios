// Mastery display widgets driven by MasteryLevel.
//
// - `MasteryBadge`: a 5-segment scale bar. Used in the 圖鑑 grid and list rows.
// - `MasteryBar`: tier name + score + progress bar. Used on the word detail page,
//   which is the only place mastery appears as words rather than as a shape.
//
// Why the badge lost its text: every tile in the grid repeated the same sentence
// ("未學", "未學", "未學"…), and the pill sat on top of the artwork it was
// describing. A bar under the image lets a whole screenful of tiles be read at a
// glance — the amount of teal *is* the answer.
//
// Because the shape carries meaning that used to be carried by a `Text`, and a
// bare shape is invisible to VoiceOver, the accessibility label here is not
// decoration — it is the only thing keeping the information available.

import SwiftUI

/// 5-segment mastery scale for word tiles and list rows.
struct MasteryBadge: View {
    let level: MasteryLevel
    /// Raw 0–100 score, when known. Only used for the spoken value.
    var score: Int?

    private static let segments = 5
    private static let width: CGFloat = 40
    /// C.9 writes "高 `bw2` 4" but B.6 defines `bw2` as 2 — the spec contradicts
    /// itself. At 2pt the five segments are not readable at arm's length, so the
    /// stated 4 wins; the bar's height is its own value, not a border width.
    private static let height: CGFloat = 4

    var body: some View {
        HStack(spacing: 1) {
            ForEach(0..<Self.segments, id: \.self) { index in
                Rectangle()
                    .fill(self.fill(at: index))
            }
        }
        .frame(width: Self.width, height: Self.height)
        .accessibilityElement()
        .accessibilityLabel(Text(self.level.name))
        .accessibilityValue(self.spokenValue)
    }

    /// 全精通 fills the whole bar in ink rather than teal — the same "this one is
    /// complete" inversion the rest of the system uses for a selected state.
    private func fill(at index: Int) -> Color {
        guard index < self.level.filledSegments else { return .tujiPaper3 }
        return self.level == .expert ? .tujiInk : .tujiTeal
    }

    private var spokenValue: Text {
        if let score { return Text("\(score) 分") }
        return Text("尚無紀錄")
    }
}

/// Tier name + score + progress bar for the word detail page. A nil score
/// (no user_words row) renders as 未學 with a "尚無紀錄" note and empty bar.
struct MasteryBar: View {
    let score: Int?
    /// Soonest scheduled review, when the word has one. The 圖鑑 grid has shown
    /// this since the countdown was written; the detail page — the one screen
    /// devoted to a single word — could not answer "when do I see this again?"
    /// at all.
    var nextReview: Date?

    private var level: MasteryLevel {
        MasteryLevel.from(score: self.score)
    }

    private var ratio: CGFloat {
        guard let s = self.score else { return 0 }
        return CGFloat(max(0, min(100, s))) / 100
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack(spacing: Space.s2) {
                Text(self.level.name)
                    .font(.tujiLabel)
                    .tracking(0.5)
                    .foregroundStyle(self.level.foreground)
                    .padding(.horizontal, Space.s2)
                    .padding(.vertical, 4)
                    .background(self.level.background, in: .rect(cornerRadius: Radius.r0))
                Spacer()
                if let s = self.score {
                    Text("\(s)")
                        .font(.tujiMono)
                        .foregroundStyle(.tujiInk2)
                        .contentTransition(.numericText())
                } else {
                    Text("尚無紀錄")
                        .font(.tujiLabel)
                        .tracking(0.5)
                        .foregroundStyle(.tujiInk3)
                }
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Rectangle()
                        .fill(.tujiPaper3)
                    Rectangle()
                        .fill(.tujiTeal)
                        .frame(width: geo.size.width * self.ratio)
                        .animation(Motion.ease(Motion.d3), value: self.ratio)
                }
            }
            .frame(height: Border.bw3)

            // Two Texts, not one interpolated key: `countdownLabel` already
            // returns a LocalizedStringKey whose values live in the catalogue,
            // and folding it into "下次複習 · \(…)" would mint a second set of
            // keys that say the same thing.
            if let due = self.nextReview {
                HStack(spacing: Space.s1) {
                    Text("下次複習")
                    Text(verbatim: "·")
                    Text(ReviewSchedule.countdownLabel(until: due))
                }
                .font(.tujiLabel)
                .tracking(0.5)
                .foregroundStyle(.tujiInk3)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    VStack(alignment: .leading, spacing: Space.s4) {
        HStack(spacing: Space.s3) {
            ForEach(MasteryLevel.allCases, id: \.self) { MasteryBadge(level: $0) }
        }
        MasteryBar(score: nil)
        MasteryBar(score: 24)
        MasteryBar(score: 52)
        MasteryBar(score: 73)
        MasteryBar(score: 91)
    }
    .padding(Space.s4)
    .background(.tujiPaper)
}
