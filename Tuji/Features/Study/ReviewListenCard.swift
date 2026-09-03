// 聽句's question: the sentence, blurred, with its audio — and the two pictures
// to choose between.
//
// The sentence is drawn with a plain `Text`, never `InteractiveSentenceText`.
// The queue deliberately carries no `spans` for it (see `StudyExample`), and a
// sentence that looks tappable and is not is worse than one that never
// pretended — the exact failure `scripts/check-gloss-host.py` exists to catch
// on the screens that *do* render 詞塊. The tappable version of this same
// sentence is one pull-up away in the reveal sheet, where the detail fetch
// brings the annotation with it.
//
// The blur is a *visual* effect and VoiceOver does not see through it — it
// would simply read the sentence out, handing over the answer without the eye
// ever being pressed and therefore without the rating cost the eye carries.
// So the sentence is hidden from the accessibility tree until it is revealed,
// and the eye is a real control in `accessibilityActions`. Same shape
// `ReviewHeroCard` uses for the hint flip, and for the same stated reason: a
// user who cannot see the picture also cannot poke at it to find out.
//
// The two pictures keep their word as a label, though. Hiding the sentence
// removes a shortcut — reading the answer instead of hearing it. The pictures
// are not a shortcut, they are the options; labelling them "選項一 / 選項二"
// would leave a blind user flipping a coin while the SRS kept score. On that
// path 聽句 becomes "hear the sentence, pick the word", which is still the
// listening question it set out to be.

import SwiftUI

struct ReviewListenCard: View {
    let coord: ReviewFlowCoordinator
    let example: StudyExample
    let height: CGFloat

    @Environment(SettingsStore.self) private var settings
    @Environment(\.targetLanguage) private var session
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var voice: SpeechService.Voice {
        .preferred(
            for: self.settings.current,
            language: self.coord.current?.word.taggedLanguage
        )
    }

    var body: some View {
        Color.tujiPaper2
            .frame(height: self.height)
            .overlay {
                Text(self.example.sentence)
                    .font(.tujiBody)
                    .foregroundStyle(.tujiInk)
                    .multilineTextAlignment(.center)
                    .lineSpacing(6)
                    .padding(.horizontal, Space.s4)
                    // 12pt leaves the shape of the words — line count, where
                    // it breaks — without leaving a single letter legible.
                    // Enough to say "there is a sentence here", which is what
                    // makes the eye mean something.
                    .blur(radius: self.coord.sentenceRevealed ? 0 : 12)
                    .animation(
                        self.reduceMotion ? .none : .easeOut(duration: 0.28),
                        value: self.coord.sentenceRevealed
                    )
                    // Even blurred, the glyphs are still selectable/readable to
                    // the system. Only the revealed sentence exists for
                    // VoiceOver.
                    .accessibilityHidden(!self.coord.sentenceRevealed)
            }
            .overlay(alignment: .bottomTrailing) { self.playButton.padding(Space.s3) }
            .overlay(alignment: .bottomLeading) { self.eyeButton.padding(Space.s3) }
            .accessibilityElement(children: .contain)
            .accessibilityLabel(
                self.coord.sentenceRevealed
                    ? Text(self.example.sentence)
                    : Text("例句（已遮蔽）")
            )
            .accessibilityActions {
                Button("再聽一次") { self.replay() }
                if !self.coord.sentenceRevealed {
                    Button("顯示例句") { self.coord.revealSentence() }
                }
            }
    }

    /// Always available, and unlimited. The clock stops being a stopwatch the
    /// user can lose by pressing this — a replay does not reset it, it just
    /// spends time that honestly means the word was hard (ADR-0014) — so there
    /// is no reason to make hearing it again feel expensive.
    private var playButton: some View {
        Button {
            self.replay()
        } label: {
            ZStack {
                Rectangle().fill(
                    self.coord.isPlayingSentence ? Color.tujiCurrent : Color.tujiPaper
                )
                Image(systemName: "speaker.wave.2.fill")
                    .font(.tujiIcon(18, weight: .semibold))
                    .foregroundStyle(.tujiInk)
            }
            .frame(width: 48, height: 48)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("再聽一次"))
    }

    /// Drawn from the first frame, unlike 選字's hint which is deliberately
    /// invisible for 8 seconds. That delay compensates for an affordance with
    /// nothing on screen to announce it; this one is on screen.
    @ViewBuilder
    private var eyeButton: some View {
        if !self.coord.sentenceRevealed {
            Button {
                self.coord.revealSentence()
            } label: {
                ZStack {
                    Rectangle().fill(.tujiPaper)
                    Image(systemName: "eye")
                        .font(.tujiIcon(18, weight: .semibold))
                        .foregroundStyle(.tujiInk2)
                }
                .frame(width: 48, height: 48)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("顯示例句"))
        }
    }

    private func replay() {
        let voice = self.voice
        Task { await self.coord.replaySentence(voice: voice) }
    }
}

// MARK: - The two pictures

/// Side by side, equal squares. Two rather than four is the whole reason 聽句
/// never auto-rates (ADR-0014) — the trade is a 50% floor on guessing bought
/// with a mandatory reveal sheet.
struct ReviewImageChoices: View {
    let coord: ReviewFlowCoordinator
    let options: [ImageChoiceOption]

    var body: some View {
        HStack(spacing: Space.s2) {
            ForEach(self.options) { option in
                Button {
                    self.coord.pickImage(option)
                } label: {
                    WordPicture(url: option.imageURL, kind: option.imageKind)
                        .frame(maxWidth: .infinity)
                        .aspectRatio(1, contentMode: .fit)
                        .background(.tujiPaper2)
                        .overlay {
                            Rectangle()
                                .strokeBorder(self.border(option), lineWidth: 3)
                        }
                }
                .buttonStyle(.plain)
                .disabled(self.coord.phase != .answer)
                .accessibilityLabel(Text(option.word))
            }
        }
    }

    /// Reveal colours mirror `StudyOptionStyle`: the picked one goes teal when
    /// it was right and alert when it was not, and a wrong pick also lights the
    /// answer so the user sees what it was without leaving the question.
    private func border(_ option: ImageChoiceOption) -> Color {
        guard self.coord.phase == .review else { return .clear }
        let isAnswer = option.id == self.coord.current?.word.id
        let isPicked = option.word == self.coord.picked
        if isAnswer { return .tujiAccumulation }
        return isPicked ? .tujiAlert : .clear
    }
}
