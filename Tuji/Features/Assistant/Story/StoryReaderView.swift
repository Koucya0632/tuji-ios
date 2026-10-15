// 情境故事 — reading one. Narration sits on the paper; Moira's lines sit beside
// her face, the person's on the right. A Japanese line carries its kana over
// the kanji; a line has a translation under it only when the interface is not
// the language being learned. The picked words follow the story, one tap from
// their own pages — explained in the same language when there is no
// translation to lean on.
//
// The story arrives whole but is read a segment at a time: 繼續 brings in the
// next one and reads it aloud when it is a spoken line (narration is in the
// interface language, so it is not). Each spoken line keeps a speaker button
// for a replay. The words and the way out wait until the last segment is in;
// 全部顯示 skips ahead for someone who would rather read it all at once.
//
// No `Spacer` beside a line: a sentence with furigana is a `FlowLayout`, and a
// custom layout next to a spacer is offered half the row. Lines take the full
// width and are pushed aside with padding instead.

import SwiftUI

struct StoryReaderView: View {
    let story: Story
    /// What the spoken lines are in, for their voice.
    let language: TargetLanguage
    let picked: [CardWord]
    let close: () -> Void
    var speech: SpeechService = .shared

    @Environment(SettingsStore.self) private var settings

    /// How many segments are on the page. Starts at the first.
    @State private var shown = 1

    private static let faceSize: CGFloat = 32
    private static let bottomID = "story-bottom"

    private var finished: Bool {
        self.shown >= self.story.segments.count
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: Space.s4) {
                        Text(verbatim: self.story.title)
                            .font(.tujiH2)
                            .foregroundStyle(.tujiInk)
                        Text(verbatim: self.story.intro)
                            .font(.tujiBody)
                            .foregroundStyle(.tujiInk2)
                            .fixedSize(horizontal: false, vertical: true)
                        ForEach(
                            Array(self.story.segments.prefix(self.shown).enumerated()),
                            id: \.offset
                        ) { _, segment in
                            self.segment(segment)
                                .transition(.opacity.combined(with: .move(edge: .bottom)))
                        }
                        if self.finished {
                            self.words
                            BBtn(title: "換個情境再寫一個", bg: .tujiPaper2, fullWidth: true) {
                                self.speech.stop()
                                self.close()
                            }
                            .padding(.top, Space.s2)
                        }
                        Color.clear.frame(height: 1).id(Self.bottomID)
                    }
                    .padding(.horizontal, Space.s4)
                    .padding(.vertical, Space.s4)
                }
                .onChange(of: self.shown) {
                    withAnimation(Motion.ease(Motion.d2)) {
                        proxy.scrollTo(Self.bottomID, anchor: .bottom)
                    }
                }
            }
            if !self.finished {
                self.continueBar
            }
        }
        .onDisappear { self.speech.stop() }
    }

    private var continueBar: some View {
        HStack(spacing: Space.s3) {
            Button {
                self.speech.stop()
                withAnimation(Motion.ease(Motion.d2)) {
                    self.shown = self.story.segments.count
                }
            } label: {
                Text("全部顯示")
                    .font(.tujiBodySm)
                    .foregroundStyle(.tujiInk3)
                    .frame(minHeight: 44)
            }
            .buttonStyle(.plain)
            BBtn(title: "繼續", fullWidth: true, action: self.advance)
        }
        .padding(.horizontal, Space.s4)
        .padding(.vertical, Space.s3)
        .background(alignment: .top) {
            Rectangle().fill(.tujiRule).frame(height: Border.bw1)
        }
    }

    /// Brings in the next segment and, when it is spoken, reads it.
    private func advance() {
        guard !self.finished else { return }
        let next = self.story.segments[self.shown]
        withAnimation(Motion.ease(Motion.d2)) {
            self.shown += 1
        }
        if next.speaker == .narrator {
            self.speech.stop()
        } else {
            self.speech.speak(next.text, voice: .preferred(for: self.settings.current, language: self.language))
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
        HStack(alignment: .top, spacing: Space.s2) {
            self.lineText(segment)
            PronunciationButton(subject: .sentence(segment.text, language: self.language), size: 28, ground: .tujiPaper)
        }
        .padding(.horizontal, Space.s3)
        .padding(.vertical, Space.s2)
        .background(segment.speaker == .cat ? Color.tujiPaper2 : .tujiBrandPrimary.opacity(0.35))
    }

    private func lineText(_ segment: Story.Segment) -> some View {
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
