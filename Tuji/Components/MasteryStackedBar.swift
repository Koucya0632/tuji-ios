// The account's mastery spread as one bar — the depth half of 我 · 進度, beside
// 完成度's width half.
//
// Lives here rather than inside MeProgressSections because it is a display
// widget over `MasteryDistribution`, the same relationship `MasteryBar` has to
// one word's score, and its host file was already at the file-length limit.

import SwiftUI

/// The tier spread as one bar, widths in proportion to the counts.
///
/// Two rules make it honest rather than merely proportional. An empty tier is
/// **not drawn**, so a gap is a real absence rather than a rounding artefact.
/// And every tier that *does* have words gets a floor of `minSegment` before
/// the proportional share is handed out — without it a single 精通 among four
/// hundred words computes to a third of a point and disappears, which is
/// exactly the word the user most wants to see. The floors come off the top and
/// the remainder is shared, so the segments still fill the bar exactly.
struct MasteryStackedBar: View {
    let distribution: MasteryDistribution

    /// Local to this bar, deliberately not a token: `Border` is the app-wide
    /// stroke scale and a segment height is not a stroke.
    private static let height: CGFloat = 8
    private static let minSegment: CGFloat = 2

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                // The track is what an all-zero distribution draws, which is
                // also the shape of "not known yet" — so the section can wait
                // for the store without either claiming or jumping.
                Rectangle()
                    .fill(.tujiPaper3)
                HStack(spacing: 0) {
                    ForEach(self.drawn) { segment in
                        Rectangle()
                            .fill(segment.level.background)
                            .frame(width: self.width(for: segment, in: geo.size.width))
                    }
                }
            }
        }
        .frame(height: Self.height)
        .accessibilityElement()
        .accessibilityLabel(Text("熟練度"))
        .accessibilityValue(self.spokenValue)
    }

    private var drawn: [MasteryDistribution.Segment] {
        self.distribution.segments.filter { $0.words > 0 }
    }

    private func width(for segment: MasteryDistribution.Segment, in available: CGFloat) -> CGFloat {
        let total = self.distribution.total
        guard total > 0 else { return 0 }
        let floors = CGFloat(self.drawn.count) * Self.minSegment
        let shareable = max(0, available - floors)
        return Self.minSegment + shareable * CGFloat(segment.words) / CGFloat(total)
    }

    /// The bar is a shape, so VoiceOver would hear nothing without this. Reads
    /// as tier + count, in the same ladder order the bar draws.
    private var spokenValue: Text {
        guard !self.drawn.isEmpty else { return Text("尚無紀錄") }
        return self.drawn.reduce(Text(verbatim: "")) { acc, segment in
            acc + Text(segment.level.name) + Text(verbatim: " \(segment.words), ")
        }
    }
}

#Preview {
    VStack(alignment: .leading, spacing: Space.s4) {
        // Not known yet / nothing studied: the bare track.
        MasteryStackedBar(distribution: .empty)
        // A lopsided spread, which is what a real account looks like.
        MasteryStackedBar(distribution: MasteryDistribution(
            know: 60, familiar: 45, proficient: 30, expert: 12
        ))
        // One 精通 among many: the floor is what keeps it on screen.
        MasteryStackedBar(distribution: MasteryDistribution(
            know: 400, familiar: 0, proficient: 0, expert: 1
        ))
    }
    .padding(Space.s4)
    .background(.tujiPaper)
}
