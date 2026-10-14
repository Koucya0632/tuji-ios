// 情境故事 — reading one. Narration sits on the paper; Moira's lines sit beside
// her face, the person's on the right. A Japanese line carries its kana over
// the kanji; a line has a translation under it only when the interface is not
// the language being learned. The picked words follow the story, one tap from
// their own pages — explained in the same language when there is no
// translation to lean on.
//
// No `Spacer` beside a line: a sentence with furigana is a `FlowLayout`, and a
// custom layout next to a spacer is offered half the row. Lines take the full
// width and are pushed aside with padding instead.

import SwiftUI

struct StoryReaderView: View {
    let story: Story
    let picked: [CardWord]
    let close: () -> Void

    private static let faceSize: CGFloat = 32

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.s4) {
                Text(verbatim: self.story.title)
                    .font(.tujiH2)
                    .foregroundStyle(.tujiInk)
                Text(verbatim: self.story.intro)
                    .font(.tujiBody)
                    .foregroundStyle(.tujiInk2)
                    .fixedSize(horizontal: false, vertical: true)
                ForEach(Array(self.story.segments.enumerated()), id: \.offset) { _, segment in
                    self.segment(segment)
                }
                self.words
                BBtn(title: "換個情境再寫一個", bg: .tujiPaper2, fullWidth: true, action: self.close)
                    .padding(.top, Space.s2)
            }
            .padding(.horizontal, Space.s4)
            .padding(.vertical, Space.s4)
        }
    }

    @ViewBuilder
    private func segment(_ segment: Story.Segment) -> some View {
        switch segment.speaker {
        case .narrator:
            Text(verbatim: segment.text)
                .font(.tujiBodySm)
                .italic()
                .foregroundStyle(.tujiInk3)
                .fixedSize(horizontal: false, vertical: true)
        case .cat:
            HStack(alignment: .top, spacing: Space.s2) {
                Mascot(pose: .face, size: Self.faceSize)
                    .accessibilityLabel(Text(verbatim: "Moira"))
                self.line(segment)
            }
            .padding(.trailing, Space.s5)
            .frame(maxWidth: .infinity, alignment: .leading)
        case .you:
            self.line(segment)
                .padding(.leading, Space.s5 + Self.faceSize)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }

    private func line(_ segment: Story.Segment) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            if let furigana = segment.furigana, !furigana.isEmpty {
                FuriganaSentence(segments: furigana)
            } else {
                Text(verbatim: segment.text)
                    .font(.tujiBody(.strong))
                    .foregroundStyle(.tujiInk)
                    .fixedSize(horizontal: false, vertical: true)
                if let reading = segment.reading {
                    Text(verbatim: reading)
                        .font(.tujiBodySm)
                        .foregroundStyle(.tujiInk3)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            if let translation = segment.translation {
                Text(verbatim: translation)
                    .font(.tujiBodySm)
                    .foregroundStyle(.tujiInk2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, Space.s3)
        .padding(.vertical, Space.s2)
        .background(segment.speaker == .cat ? Color.tujiPaper2 : .tujiBrandPrimary.opacity(0.35))
    }

    /// The note the story gave a word, when it gave one; otherwise its gloss.
    private func explanation(for word: CardWord) -> String {
        self.story.wordNotes?.first { $0.id == word.id }?.note ?? word.chinese
    }

    private var words: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("故事裡的單字")
                .font(.tujiLabel)
                .tracking(0.5)
                .foregroundStyle(.tujiInk3)
                .padding(.bottom, Space.s1)
            ForEach(self.picked) { word in
                NavigationLink(value: NavRoute.wordDetail(id: word.id)) {
                    HStack(spacing: Space.s3) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(verbatim: word.word)
                                .font(.tujiBody(.strong))
                                .foregroundStyle(.tujiInk)
                            Text(verbatim: self.explanation(for: word))
                                .font(.tujiBodySm)
                                .foregroundStyle(.tujiInk3)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: Space.s2)
                        TujiRowAccessory()
                    }
                    .padding(.vertical, Space.s2)
                    .frame(minHeight: 52)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                Rectangle().fill(.tujiRule).frame(height: Border.bw1)
            }
        }
        .padding(.top, Space.s3)
    }
}
