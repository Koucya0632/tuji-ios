// The word's identity as a row: headword + reading + gloss on the left,
// bookmark + audio stacked on the right.
//
// It was written twice, byte for byte, in `ReviewRevealSheet.summary` and
// `WordPeekSheet.headerRow` — the same six views, the same `.layoutPriority(1)`
// and the same comment explaining it — differing only in which expression the
// word came out of. 複習's 求救提示 detail sheet needed a third, which is the
// point at which a copy becomes a component.
//
// `gloss` is `String?` rather than a `showZh` read, because the callers do not
// agree: the two sheets gate the 中文 line on that switch, and the hint sheet
// does not — `showZh` governs the *always-on* gloss 學新字 prints on a picture,
// and a deliberate tap is not that (CONTEXT.md, 求救提示).

import SwiftUI

struct WordSummaryRow: View {
    let word: any Headworded
    /// Kept beside `word` because two of the three models that satisfy
    /// `Headworded` carry no id: the bookmark needs one, the headword does not.
    let wordId: String
    /// The 中文 line. Rendered when non-nil — see the file header.
    let gloss: String?
    /// Pre-generated clips, when the caller has them. `PronunciationButton`
    /// falls back to on-device synthesis without them.
    let audioUrls: [String: String]?
    var buttonSize: CGFloat = 44

    var body: some View {
        HStack(alignment: .top, spacing: Space.s3) {
            VStack(alignment: .leading, spacing: Space.s1) {
                TujiHeadword(word: self.word)
                TujiReadingLine(word: self.word, ink: .tujiInk3)
                if let gloss = self.gloss {
                    Text(gloss)
                        .font(.tujiBodySm)
                        .foregroundStyle(.tujiInk2)
                        .padding(.top, 2)
                }
            }
            // See WordDetailView.titleRow: beside a `Spacer` the headword is
            // offered half the row unless it is prioritised.
            .layoutPriority(1)
            Spacer()
            VStack(spacing: Space.s2) {
                FavoriteButton(wordId: self.wordId, size: self.buttonSize)
                PronunciationButton(
                    text: self.word.word,
                    language: self.word.taggedLanguage,
                    audioUrls: self.audioUrls,
                    size: self.buttonSize
                )
            }
        }
    }
}
