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
                Text(self.sentence)
                    .font(.tujiBody)
                    .foregroundStyle(.tujiInk)
                    .multilineTextAlignment(.center)
                    .lineSpacing(6)
                    .padding(.horizontal, Space.s4)
                    // 12pt leaves the shape of the words — line count, where
                    // it breaks — without leaving a single letter legible.
                    // Enough to say "there is a sentence here", which is what
                    // makes the eye mean something.
                    .blur(radius: self.isLegible ? 0 : 12)
                    .animation(
                        self.reduceMotion ? .none : .easeOut(duration: 0.28),
                        value: self.isLegible
                    )
                    // Even blurred, the glyphs are still selectable/readable to
                    // the system. Only a legible sentence exists for VoiceOver.
                    .accessibilityHidden(!self.isLegible)
            }
            .overlay(alignment: .bottomTrailing) {
                HStack(spacing: Space.s2) {
                    self.slowButton
                    self.playButton
                }
                .padding(Space.s3)
            }
            .overlay(alignment: .bottomLeading) { self.eyeButton.padding(Space.s3) }
            .accessibilityElement(children: .contain)
            .accessibilityLabel(
                self.isLegible ? Text(self.example.sentence) : Text("例句（已遮蔽）")
            )
            .accessibilityActions {
                Button("再聽一次") { self.replay() }
                Button("慢速播放") { self.replay(slow: true) }
                if !self.isLegible {
                    Button("顯示例句") { self.coord.revealSentence() }
                }
            }
    }

    /// The sentence is readable once the answer is in, or once the eye bought
    /// it. Answering removes the reason to hide it: from that moment the
    /// sentence is study material, exactly like the answer on the reveal sheet,
    /// and it costs nothing — `hinted` is only ever set by `revealSentence()`,
    /// which refuses outside `.answer`.
    private var isLegible: Bool {
        self.coord.sentenceRevealed || self.coord.phase == .review
    }

    /// The sentence, with the word being asked about under a 螢光筆.
    ///
    /// Marked only while legible: highlighting under the blur would be a
    /// coloured smudge that tells the reader which shape to guess at. It *is*
    /// marked on the eye-reveal as well as after answering — that button
    /// already costs the full wrong-answer rating table, and once the sentence
    /// spells the word out, pointing at it leaks nothing further.
    private var sentence: AttributedString {
        let raw = self.example.sentence
        guard self.isLegible,
              let word = self.coord.current?.word.word,
              let match = SentenceHighlight.range(of: word, in: raw)
        else { return AttributedString(raw) }

        var marked = AttributedString(String(raw[match]))
        // 螢光筆, not a fill — the same gesture (and the same ink) the 詞塊 card
        // uses on the word it is explaining. The text underneath has to stay
        // readable through it.
        marked.backgroundColor = .tujiBrandPrimary.opacity(0.45)
        return AttributedString(String(raw[..<match.lowerBound]))
            + marked
            + AttributedString(String(raw[match.upperBound...]))
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

    /// 慢讀, at `ReviewFlowCoordinator.slowRate`.
    ///
    /// Drawn as a sibling of the speaker rather than hidden behind a long-press
    /// on it. The same reasoning the eye follows: an affordance nobody can see
    /// is found only by people who did not need it, and the person who needs a
    /// sentence read slowly is the least likely to go hunting for a gesture.
    ///
    /// The label is the number, not a tortoise — `0.8×` says exactly how much
    /// slower, in a form that needs no translating.
    private var slowButton: some View {
        Button {
            self.replay(slow: true)
        } label: {
            ZStack {
                Rectangle().fill(.tujiPaper)
                Text(verbatim: "0.8×")
                    .font(.tujiMono)
                    .foregroundStyle(.tujiInk2)
            }
            .frame(width: 48, height: 48)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("慢速播放"))
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

    private func replay(slow: Bool = false) {
        let voice = self.voice
        Task { await self.coord.replaySentence(voice: voice, slow: slow) }
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
                    // The *container* holds the square, not the picture.
                    // `WordPicture` fits its image whole and never crops, so
                    // putting `.aspectRatio` on it lets each picture's own
                    // proportions through — a wide MRT photo sat short beside a
                    // square intersection and the two options came out ragged.
                    // `WordTile` had already learned this and written it down;
                    // this is the same rule, and copying the idiom rather than
                    // re-deriving it is the point.
                    Color.tujiPaper2
                        .aspectRatio(1, contentMode: .fit)
                        .frame(maxWidth: .infinity)
                        .overlay { WordPicture(url: option.imageURL, kind: option.imageKind) }
                        .clipped()
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
