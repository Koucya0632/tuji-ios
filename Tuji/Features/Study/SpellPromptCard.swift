// The prompt half of a 拼字 card: the picture, the gloss and the speaker.
//
// Shared by both spelling boards — 拼字塊 (TilesView) and 挖空拼字
// (SpellGapView). It was TilesView's private `card` + `hero` pair until the
// gap-fill needed the identical thing; copying it would have made the image
// blend mode, the corner radius and the gloss gate three rules living in two
// places, which is how they drift.

import SwiftUI

struct SpellPromptCard: View {
    let word: StudyQueueWord
    /// Whether the gloss belongs on this board.
    ///
    /// 拼字塊 hides the string it is asking for, so the gloss is the only cue
    /// besides the picture and has to stay. 挖空拼字 already shows the word with
    /// holes in it, so the gloss says nothing the prompt has not — and on a word
    /// whose hole is most of a syllable it edges towards handing over the answer.
    let showsGloss: Bool

    @Environment(SettingsStore.self) private var settings

    var body: some View {
        VStack(spacing: Space.s3) {
            self.hero
            HStack {
                if self.showsGloss, self.settings.current.showZh {
                    Text(self.word.chinese)
                        .font(.tujiBodySm(.strong))
                        .foregroundStyle(.tujiInk)
                }
                Spacer()
                PronunciationButton(
                    subject: SpokenWord(self.word),
                    size: 36
                )
            }
            .padding(.horizontal, Space.s3)
            .padding(.bottom, Space.s3)
        }
        .background(.tujiPaper, in: .rect(cornerRadius: Radius.r0))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.r0)
                .stroke(.tujiRule.opacity(0.15), lineWidth: 1)
        )
    }

    private var hero: some View {
        ZStack {
            Rectangle().fill(.tujiPaper)
            // This screen used to hard-code `.fit` with no blend mode at all,
            // so a dictionary cut-out kept the white rectangle every other
            // screen multiplies away — the one place the 紙與墨 fix never
            // reached.
            WordPicture(
                url: self.word.imageURL,
                kind: self.word.imageKind,
                inset: Space.s2,
                glyphSize: 28
            )
        }
        .frame(height: 168)
        .clipped()
        .clipShape(.rect(topLeadingRadius: Radius.r0, topTrailingRadius: Radius.r0))
    }
}
