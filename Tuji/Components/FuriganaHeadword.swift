// A Japanese headword with its kana set over the characters they read.
//
// Replaces the line that used to sit *under* the word, where the reader had to
// work out which kana went with which kanji: はみがきこ under 歯磨き粉 says
// nothing about 磨 being みが. The split itself is a server-side dictionary
// fact (see `FuriganaSegment`); this file is only about drawing it.
//
// Only the display-size screens use this. A correctly proportioned ruby is half
// the base size, and the 圖鑑 grid sets its headword in `tujiH3` (18pt), so its
// ruby would land on 9pt — inside the range TujiFont.swift removed on purpose,
// because CJK strokes merge there. The grid therefore keeps the reading line.
//
// `.minimumScaleFactor` is not usable here. It shrinks each `Text` on its own,
// so a row of separate segments would come out at a different size per segment.
// The layout below measures the whole row, decides one scale for all of it, and
// proposes each segment the width that produces that scale.

import SwiftUI

struct FuriganaHeadword: View {
    let segments: [FuriganaSegment]
    /// Point size of the headword. Ruby is drawn at `rubyRatio` of it.
    var baseSize: CGFloat
    var rubyRatio: CGFloat = 0.5
    /// Ruby sits closer to its base than normal line spacing would put it.
    var rubySpacing: CGFloat = 1
    var maxLines: Int = 2
    /// Matches the `.minimumScaleFactor(0.5)` the plain headwords already use.
    var minScale: CGFloat = 0.5

    var body: some View {
        FuriganaLayout(maxLines: self.maxLines, minScale: self.minScale) {
            ForEach(Array(self.segments.enumerated()), id: \.offset) { _, segment in
                VStack(spacing: self.rubySpacing) {
                    // Every segment reserves the ruby line, including the ones
                    // with no ruby: without it the bare kana of 歯磨"き"粉 would
                    // sit a ruby's height higher than its neighbours.
                    Text(segment.ruby ?? " ")
                        .font(.tujiFuriganaRuby(self.baseSize * self.rubyRatio))
                        .foregroundStyle(.tujiInk3)
                        .lineLimit(1)
                    Text(segment.text)
                        .font(.tujiFuriganaBase(self.baseSize))
                        .foregroundStyle(.tujiInk)
                        .lineLimit(1)
                }
                .fixedSize(horizontal: true, vertical: false)
            }
        }
        // Segment-by-segment, VoiceOver would read 歯・磨・き・粉 as four items
        // and then say the kana twice over. One label, the word as written.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(self.segments.map(\.text).joined())
    }
}

/// A headword, with its kana over it when there are kana to place.
///
/// Draws only the word. The kana *line* — what `.line` means — stays where each
/// screen already puts it, because those places differ: the detail screens sit
/// it in a row beside the part of speech and the CEFR chip, 認識 gives it a row
/// of its own. Moving it would have rearranged four screens to no purpose.
struct TujiHeadword: View {
    let display: HeadwordDisplay
    let word: String
    /// The headword's point size, so ruby can be derived from it. Must match
    /// whatever font the screen would otherwise have set.
    var baseSize: CGFloat
    var font: Font
    var maxLines: Int = 2
    var minScale: CGFloat = 0.5

    var body: some View {
        switch self.display {
        case let .ruby(segments):
            FuriganaHeadword(
                segments: segments,
                baseSize: self.baseSize,
                maxLines: self.maxLines,
                minScale: self.minScale
            )
        case .line, .plain:
            Text(self.word)
                .font(self.font)
                .foregroundStyle(.tujiInk)
                .lineLimit(self.maxLines)
                .minimumScaleFactor(self.minScale)
        }
    }
}

/// Places furigana segments in a row, wrapping before it shrinks.
///
/// Wrapping first is what the plain headwords already do — `.lineLimit(2)`
/// before `.minimumScaleFactor(0.5)` — and it matters more here: 10% of the
/// catalogue's kanji words overrun a phone's detail column once ruby widens
/// them, but none overruns two lines, so scaling is a last resort that almost
/// never fires.
struct FuriganaLayout: Layout {
    var maxLines: Int
    var minScale: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let widths = subviews.map { $0.sizeThatFits(.unspecified).width }
        let height = subviews.map { $0.sizeThatFits(.unspecified).height }.max() ?? 0
        let solution = FuriganaWrap.solve(
            widths: widths,
            available: proposal.width ?? .infinity,
            maxLines: self.maxLines,
            minScale: self.minScale
        )
        let widest = solution.lines
            .map { line in line.reduce(0) { $0 + widths[$1] * solution.scale } }
            .max() ?? 0
        return CGSize(
            width: widest,
            height: height * solution.scale * CGFloat(solution.lines.count)
        )
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        let widths = sizes.map(\.width)
        let rowHeight = sizes.map(\.height).max() ?? 0
        let solution = FuriganaWrap.solve(
            widths: widths,
            available: bounds.width,
            maxLines: self.maxLines,
            minScale: self.minScale
        )
        let scaledRow = rowHeight * solution.scale

        var y = bounds.minY
        for line in solution.lines {
            var x = bounds.minX
            for index in line {
                let width = widths[index] * solution.scale
                subviews[index].place(
                    at: CGPoint(x: x, y: y),
                    anchor: .topLeading,
                    // Proposing the scaled width is what performs the scaling:
                    // each segment's `Text` fits itself to what it is given, and
                    // since every segment is offered the same fraction of its
                    // natural width, they all end up at the same size.
                    proposal: ProposedViewSize(width: width, height: scaledRow)
                )
                x += width
            }
            y += scaledRow
        }
    }
}

/// Where the line breaks fall and how much the row has to shrink.
///
/// Pure, so the awkward cases can be tested without a view: a single segment
/// wider than the whole column, a row that fits exactly, one that needs the
/// floor scale.
enum FuriganaWrap {
    struct Solution: Equatable {
        var scale: CGFloat
        /// Indices of the segments on each line, in order.
        var lines: [[Int]]
    }

    static func solve(
        widths: [CGFloat],
        available: CGFloat,
        maxLines: Int,
        minScale: CGFloat
    )
        -> Solution
    {
        guard !widths.isEmpty else { return Solution(scale: 1, lines: []) }
        guard available.isFinite, available > 0 else {
            return Solution(scale: 1, lines: [Array(widths.indices)])
        }

        // The largest scale that still wraps into `maxLines`. Search rather than
        // solve: how many lines a scale needs is a step function of it, because
        // a break only moves when a segment crosses the edge.
        var low = max(0.01, minScale)
        var high: CGFloat = 1
        if self.wrap(widths: widths, available: available, scale: high).count <= maxLines {
            return Solution(scale: high, lines: self.wrap(widths: widths, available: available, scale: high))
        }
        for _ in 0..<12 {
            let mid = (low + high) / 2
            if self.wrap(widths: widths, available: available, scale: mid).count <= maxLines {
                low = mid
            } else {
                high = mid
            }
        }
        // `low` is the floor when nothing fits — a very long word then overruns
        // rather than becoming unreadable, which is what the old headword did.
        return Solution(scale: low, lines: self.wrap(widths: widths, available: available, scale: low))
    }

    private static func wrap(widths: [CGFloat], available: CGFloat, scale: CGFloat) -> [[Int]] {
        var lines: [[Int]] = []
        var current: [Int] = []
        var x: CGFloat = 0
        for (index, width) in widths.enumerated() {
            let scaled = width * scale
            if !current.isEmpty, x + scaled > available {
                lines.append(current)
                current = []
                x = 0
            }
            current.append(index)
            x += scaled
        }
        if !current.isEmpty { lines.append(current) }
        return lines
    }
}

#Preview {
    VStack(alignment: .leading, spacing: 32) {
        FuriganaHeadword(
            segments: [
                FuriganaSegment(text: "歯", ruby: "は"),
                FuriganaSegment(text: "磨", ruby: "みが"),
                FuriganaSegment(text: "き", ruby: nil),
                FuriganaSegment(text: "粉", ruby: "こ")
            ],
            baseSize: 56
        )
        FuriganaHeadword(
            segments: [
                FuriganaSegment(text: "目", ruby: "め"),
                FuriganaSegment(text: "覚", ruby: "ざ"),
                FuriganaSegment(text: "ま", ruby: nil),
                FuriganaSegment(text: "し", ruby: nil),
                FuriganaSegment(text: "時計", ruby: "どけい")
            ],
            baseSize: 56
        )
        FuriganaHeadword(
            segments: [FuriganaSegment(text: "豆板醤", ruby: "トウバンジャン")],
            baseSize: 56
        )
        FuriganaHeadword(
            segments: [
                FuriganaSegment(text: "鶏", ruby: "にわとり"),
                FuriganaSegment(text: "ガ", ruby: nil),
                FuriganaSegment(text: "ラ", ruby: nil),
                FuriganaSegment(text: "ス", ruby: nil),
                FuriganaSegment(text: "ー", ruby: nil),
                FuriganaSegment(text: "プ", ruby: nil),
                FuriganaSegment(text: "の", ruby: nil),
                FuriganaSegment(text: "素", ruby: "もと")
            ],
            baseSize: 56
        )
    }
    .padding()
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(.tujiPaper)
}
