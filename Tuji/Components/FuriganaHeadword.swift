// A Japanese headword with its kana set over the characters they read.
//
// Replaces the line that used to sit *under* the word, where the reader had to
// work out which kana went with which kanji: はみがきこ under 歯磨き粉 says
// nothing about 磨 being みが. The split itself is a server-side dictionary
// fact (see `FuriganaSegment`); this file is only about drawing it.
//
// Every screen that shows a headword uses this, at one size. The 圖鑑 grid does
// not: it sets its words in `tujiH3` (18pt), and a correctly proportioned ruby
// there would land on 9pt — inside the range TujiFont.swift removed on purpose,
// because CJK strokes merge. The grid therefore keeps the reading line.
//
// The word is fitted to its column by *choosing a size*, not by scaling a laid
// out row. Each candidate below is already drawn at its final point size, so
// there is no gap between what the layout measures and what the glyphs paint —
// which is exactly what the previous version got wrong: it computed a scale,
// placed segments at scaled offsets, and then let each `Text` draw at full size
// on top of its neighbour. That never showed because a two-line row absorbed
// every catalogue word and the scale stayed at 1.

import SwiftUI

struct FuriganaHeadword: View {
    let segments: [FuriganaSegment]
    /// Point size of the headword at full size. Ruby is `rubyRatio` of it.
    var baseSize: CGFloat
    var rubyRatio: CGFloat = 0.5
    /// Ruby sits closer to its base than normal line spacing would put it.
    var rubySpacing: CGFloat = 1

    private var steps: [CGFloat] {
        FuriganaScaleLadder.steps(baseSize: self.baseSize, rubyRatio: self.rubyRatio)
    }

    /// Clamped, so the rungs can be written out as distinct views even when the
    /// ladder collapses to a single size.
    private func step(_ index: Int) -> CGFloat {
        let steps = self.steps
        return steps[min(index, steps.count - 1)]
    }

    var body: some View {
        // `ViewThatFits` takes the first candidate whose ideal width fits the
        // column, and falls back to the last one when none does. Spelled out
        // rather than looped: a `ForEach` would hand it one collection where it
        // needs separate views to choose between.
        ViewThatFits(in: .horizontal) {
            self.row(scale: self.step(0))
            self.row(scale: self.step(1))
            self.row(scale: self.step(2))
            self.row(scale: self.step(3))
            self.row(scale: self.step(4))
        }
        // Segment-by-segment, VoiceOver would read 歯・磨・き・粉 as four items
        // and then say the kana twice over. One label, the word as written.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(self.segments.map(\.text).joined())
    }

    private func row(scale: CGFloat) -> some View {
        HStack(spacing: 0) {
            ForEach(Array(self.segments.enumerated()), id: \.offset) { _, segment in
                VStack(spacing: self.rubySpacing * scale) {
                    // Every segment reserves the ruby line, including the ones
                    // with no ruby: without it the bare kana of 歯磨"き"粉 would
                    // sit a ruby's height higher than its neighbours.
                    Text(segment.ruby ?? " ")
                        .font(.tujiHeadwordRuby(self.baseSize * self.rubyRatio * scale))
                        .foregroundStyle(.tujiInk3)
                        .lineLimit(1)
                    Text(segment.text)
                        .font(.tujiHeadword(self.baseSize * scale))
                        .foregroundStyle(.tujiInk)
                        .lineLimit(1)
                }
                .fixedSize()
            }
        }
        // Report the natural width, so `ViewThatFits` compares the size this row
        // actually wants against the column rather than a compressed one.
        .fixedSize(horizontal: true, vertical: false)
    }
}

/// The sizes a furigana headword is allowed to take, largest first.
///
/// The bottom of the ladder is not a taste decision: below roughly 13pt CJK
/// strokes merge, which is why `TujiFont.swift` removed that end of the scale
/// outright. Ruby is half the headword, so *the headword's* floor is whatever
/// keeps the ruby legible — 0.47 under a 56pt word, but 0.77 under a 34pt one.
/// Deriving it here makes that constraint something the code enforces instead
/// of something a call site is trusted to remember.
///
/// At the 26pt `TujiHeadword` now sets, the floor *is* full size and the ladder
/// collapses to a single rung. That is the correct answer, not a degenerate one:
/// there is no room left to shrink into, and every kanji word in the catalogue
/// fits at 26pt anyway.
enum FuriganaScaleLadder {
    /// Smallest kana the CJK face still resolves; see TujiFont.swift.
    static let minimumRubyPoint: CGFloat = 13

    static func steps(
        baseSize: CGFloat,
        rubyRatio: CGFloat = 0.5,
        minRubyPoint: CGFloat = FuriganaScaleLadder.minimumRubyPoint
    )
        -> [CGFloat]
    {
        let rubyAtFullSize = baseSize * rubyRatio
        guard rubyAtFullSize > 0 else { return [1] }

        // A base so small that even full size breaks the floor still has to
        // draw something; one rung at full size is the honest answer.
        let floor = min(1, minRubyPoint / rubyAtFullSize)
        guard floor < 1 else { return [1] }

        // Five rungs spread over the usable range. Evenly spaced rather than
        // tuned: the gap only decides how much smaller than necessary a word
        // ends up, and at this many rungs that is under 5%.
        let rungs = 5
        return (0..<rungs).map { index in
            1 - (1 - floor) * CGFloat(index) / CGFloat(rungs - 1)
        }
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
    /// One size for every headword on every screen.
    ///
    /// A size only short words got to keep is not a hierarchy: at 56pt, 洗剤 was
    /// set twice as large as シャワーカーテンポール purely because it is shorter.
    /// 26pt is where that stops — 478 of the 480 Japanese words fit their column
    /// outright, so they all render identically.
    ///
    /// It is also the floor. Ruby is half the headword and the CJK face stops
    /// resolving below 13pt (TujiFont.swift), so 26 is the smallest headword that
    /// can carry legible kana; the two remaining outliers have no kanji, so they
    /// shrink without a ruby to protect.
    ///
    /// Defaulted rather than passed: five screens were handing over the same
    /// constants, and this feature has already been bitten once by a decision
    /// living in five places.
    var baseSize: CGFloat = 26
    /// Decides whether the word may wrap. nil is treated as "not Japanese",
    /// which is the safe direction: wrapping never truncates.
    var language: TargetLanguage?

    /// Japanese is written without spaces, so a wrapped headword breaks in the
    /// middle of a word — シャワーカー / テンポール. It is fitted onto one line
    /// instead, which is what the ruby ladder does anyway. English wraps at
    /// spaces, where a second line reads perfectly well, so it keeps wrapping;
    /// forcing it onto one line only made the longest phrases shrink until they
    /// truncated.
    private var wrapsOntoASecondLine: Bool {
        self.language != .ja
    }

    var body: some View {
        switch self.display {
        case let .ruby(segments):
            FuriganaHeadword(segments: segments, baseSize: self.baseSize)
        case .line, .plain:
            Text(self.word)
                .font(.tujiHeadword(self.baseSize))
                .foregroundStyle(.tujiInk)
                .lineLimit(self.wrapsOntoASecondLine ? 2 : 1)
                // No ruby here, so the 13pt CJK floor does not apply and the
                // only limit is legibility. One line has to shrink much further
                // than two: the longest kana headword (12em) needs 0.43 of a
                // 56pt size. Two lines need 0.5 rather than the 0.6 they used to
                // allow — "chicken bouillon powder" wraps to "bouillon powder",
                // which wants 0.575, and a floor above that made it truncate to
                // "chicken bouillon powd…" instead of shrinking.
                .minimumScaleFactor(self.wrapsOntoASecondLine ? 0.5 : 0.4)
        }
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
            baseSize: 26
        )
        FuriganaHeadword(
            segments: [
                FuriganaSegment(text: "目", ruby: "め"),
                FuriganaSegment(text: "覚", ruby: "ざ"),
                FuriganaSegment(text: "ま", ruby: nil),
                FuriganaSegment(text: "し", ruby: nil),
                FuriganaSegment(text: "時計", ruby: "どけい")
            ],
            baseSize: 26
        )
        FuriganaHeadword(
            segments: [FuriganaSegment(text: "豆板醤", ruby: "トウバンジャン")],
            baseSize: 26
        )
        // The widest ruby-bearing word in the catalogue (9.0em). At 26pt it
        // fits a phone's detail column outright, so nothing shrinks.
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
            baseSize: 26
        )
    }
    .padding()
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(.tujiPaper)
}
