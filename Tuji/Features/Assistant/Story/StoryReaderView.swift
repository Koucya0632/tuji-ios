// 情境故事 — reading one. Narration sits on the paper; Moira's lines sit beside
// her face, the person's on the right. A Japanese line carries its kana over
// the kanji; a line has a translation under it only when the interface is not
// the language being learned. The picked words follow the story, one tap from
// their own pages — explained in the same language when there is no
// translation to lean on.
//
// The story arrives a segment at a time while Moira is still writing it — the
// page opens the moment 生成故事 is tapped, empty until the title and intro
// come in — and is read a segment at a time: 繼續
// brings in the next one that has arrived, and when the reader has caught up
// with the writing the bar says so instead. 繼續 brings in the
// next one and reads it aloud when it is a spoken line (narration is in the
// interface language, so it is not). Each spoken line keeps a speaker button
// for a replay, and a mic under it for 跟讀 — reading the line back and seeing
// what was heard (`StoryShadowing`). Moving on, or replaying a line, drops a
// try in progress. The words and the way out wait until the last segment is in;
// 全部顯示 skips ahead for someone who would rather read it all at once.
//
// No `Spacer` beside a line: a sentence with furigana is a `FlowLayout`, and a
// custom layout next to a spacer is offered half the row. Lines take the full
// width and are pushed aside with padding instead.

import SwiftUI

struct StoryReaderView: View {
    /// Nil until the title and intro have arrived.
    let story: Story?
    /// What the spoken lines are in, for their voice.
    let language: TargetLanguage
    let picked: [CardWord]
    /// `.writing` while segments are still arriving; `.failed` when the
    /// writing stopped partway.
    let writing: StoryBuilderModel.Writing
    let close: () -> Void
    var speech: SpeechService = .shared

    @Environment(SettingsStore.self) private var settings

    /// How many segments are on the page. Starts at the first.
    @State private var shown = 1
    @State private var recorder = ShadowingRecorder()

    private static let faceSize: CGFloat = 32
    private static let bottomID = "story-bottom"

    private var segments: [Story.Segment] {
        self.story?.segments ?? []
    }

    private var caughtUp: Bool {
        self.shown >= self.segments.count
    }

    private var finished: Bool {
        self.caughtUp && self.writing != .writing
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: Space.s4) {
                        if let story = self.story {
                            Text(verbatim: story.title)
                                .font(.tujiH2)
                                .foregroundStyle(.tujiInk)
                            Text(verbatim: story.intro)
                                .font(.tujiBody)
                                .foregroundStyle(.tujiInk2)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        ForEach(
                            Array(self.segments.prefix(self.shown).enumerated()),
                            id: \.offset
                        ) { index, segment in
                            self.segment(segment, index: index)
                                .transition(.opacity.combined(with: .move(edge: .bottom)))
                        }
                        if self.finished {
                            if case let .failed(failure) = self.writing {
                                Text(verbatim: StoryBuilderView.sentence(for: failure))
                                    .font(.tujiBodySm)
                                    .foregroundStyle(.tujiInk3)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            self.words
                            BBtn(title: "換個情境再寫一個", bg: .tujiPaper2, fullWidth: true) {
                                self.speech.stop()
                                self.recorder.cancel()
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
        .onDisappear {
            self.speech.stop()
            self.recorder.cancel()
        }
    }

    private var continueBar: some View {
        HStack(spacing: Space.s3) {
            if self.caughtUp {
                HStack(spacing: Space.s2) {
                    TujiProgressBar(progress: nil).frame(width: 40)
                    Text("Moira 正在寫故事…")
                        .font(.tujiBodySm)
                        .foregroundStyle(.tujiInk)
                }
                .frame(maxWidth: .infinity, minHeight: 52)
            } else {
                self.advanceButtons
            }
        }
        .padding(.horizontal, Space.s4)
        .padding(.vertical, Space.s3)
        .background(alignment: .top) {
            Rectangle().fill(.tujiRule).frame(height: Border.bw1)
        }
    }

    @ViewBuilder
    private var advanceButtons: some View {
        Button {
            self.speech.stop()
            self.recorder.cancel()
            withAnimation(Motion.ease(Motion.d2)) {
                self.shown = self.segments.count
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

    /// Brings in the next segment and, when it is spoken, reads it.
    private func advance() {
        guard !self.caughtUp else { return }
        let next = self.segments[self.shown]
        self.recorder.cancel()
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
    private func segment(_ segment: Story.Segment, index: Int) -> some View {
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
                self.line(segment, index: index)
            }
            .padding(.trailing, Space.s5)
            .frame(maxWidth: .infinity, alignment: .leading)
        case .you:
            self.line(segment, index: index)
                .padding(.leading, Space.s5 + Self.faceSize)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }

    private func line(_ segment: Story.Segment, index: Int) -> some View {
        HStack(alignment: .top, spacing: Space.s2) {
            VStack(alignment: .leading, spacing: 0) {
                self.lineText(segment)
                ShadowingFeedback(recorder: self.recorder, line: index, language: self.language)
            }
            VStack(spacing: Space.s1) {
                PronunciationButton(
                    subject: .sentence(segment.text, language: self.language),
                    size: 28,
                    ground: .tujiPaper
                )
                .simultaneousGesture(TapGesture().onEnded { self.recorder.cancel() })
                ShadowingButton(recorder: self.recorder, line: index, target: segment.text, language: self.language)
            }
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
        self.story?.wordNotes?.first { $0.id == word.id }?.note ?? word.chinese
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
