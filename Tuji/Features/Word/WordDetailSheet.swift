// One word's full detail, as a bottom sheet — the whole word, not the peek.
//
// Named for what it is rather than for who opens it: 複習's 求救提示 is the
// first caller, and a module named after one of its callers does not get found
// by the next one (CONTEXT.md, `TileBoard` / `ImageIntake`).
//
// The summary row draws from the payload the caller already has, so the word,
// its reading and its gloss are on screen before any request goes out; the
// sections below arrive when `ExpandableWordDetail` finishes loading. That
// loader is reused rather than rewritten because it is the piece that knows an
// `atlas:` id is a 自製圖鑑 item — the exact bug its own file header records.
//
// No analytics, for the reason `ExpandableWordDetail` gives: a peek inside a
// study session is not a page view.
//
// **A caller must host the 詞塊 card** — `.glossCard()`, on the sheet root
// *outside* whatever shell draws the title bar. `InteractiveSentenceText` makes
// nothing tappable without a host (a live link with nowhere to deliver its tap
// reads as broken, so it falls back to plain text), and the card's scrim is an
// overlay on whatever hosts it: attached in here it would stop below the shell's
// header, leaving the title bar lit and its ✕ live underneath a modal card.
// The card is an overlay rather than a sheet precisely so it can live in a sheet.

import SwiftUI

struct WordDetailSheet: View {
    let word: any Headworded
    let wordId: String
    let gloss: String
    let audioUrls: [String: String]?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.s3) {
                WordSummaryRow(
                    word: self.word,
                    wordId: self.wordId,
                    gloss: self.gloss,
                    audioUrls: self.audioUrls
                )
                ExpandableWordDetail(wordId: self.wordId, expanded: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Space.s4)
            .padding(.top, Space.s3)
            .padding(.bottom, Space.s5)
        }
    }
}
