// Step 3 of NewFlow: show a spelling (deterministically correct on even
// attempts, deliberately wrong on odd) and ask whether it's correct.
// Practice-only — wrong judgments requeue without writing SRS.

import Nuke
import NukeUI
import SwiftUI

struct SpellView: View {
    let coord: NewFlowCoordinator
    let item: StudyQueueItem

    @Environment(SettingsStore.self) private var settings

    var body: some View {
        VStack(spacing: Space.s4) {
            self.bubble
            self.card
            Spacer(minLength: 0)
            self.buttons
        }
        .padding(.horizontal, Space.s6)
        .padding(.bottom, Space.s5)
    }

    private var shown: String {
        self.coord.spellShown(for: self.item)
    }

    /// The canonical correct answer being quizzed — the hiragana reading for
    /// JA words, else the term form.
    private var subject: String {
        self.coord.spellSubject(for: self.item)
    }

    /// True when Part 3 is judging a kana reading (JA): hide the kanji until
    /// the user answers and ask about the reading.
    private var isReadingMode: Bool {
        self.coord.spellUsesReading(for: self.item)
    }

    private var shownIsCorrect: Bool {
        self.shown == self.subject
    }

    /// True once the user has judged (locked). spJudge and spLocked are always
    /// set/cleared together by the coordinator, so this is the "show result" gate.
    private var judged: Bool {
        self.coord.spLocked && self.coord.spJudge != nil
    }

    /// Whether the user's 對/錯 judgment matched reality. Only meaningful when
    /// `judged`.
    private var judgedRight: Bool {
        (self.coord.spJudge == .yes) == self.shownIsCorrect
    }

    /// The judgment the user *should* have tapped (對 if the shown spelling is
    /// correct, otherwise 錯). Used to highlight the right answer.
    private var correctSay: JudgeAnswer {
        self.shownIsCorrect ? .yes : .no
    }

    @ViewBuilder
    private var bubble: some View {
        if self.judged {
            MascotSpeechBubble(
                pose: self.judgedRight ? .cheer : .think,
                text: self.judgedRight ? "答對了！" : "答錯了",
                tone: self.judgedRight ? .success : .error,
                systemImage: self.judgedRight ? "checkmark.circle.fill" : "xmark.circle.fill"
            )
        } else {
            MascotSpeechBubble(
                pose: .think,
                text: self.isReadingMode
                    ? "這個讀音正確嗎？"
                    : (self.settings.current.learningDirection == .zhJa
                        ? "這個日文詞形正確嗎？"
                        : "這個字拼對了嗎？")
            )
        }
    }

    private var card: some View {
        VStack(spacing: Space.s4) {
            self.hero
            VStack(spacing: Space.s2) {
                Text(self.shown)
                    .font(.system(size: 30, weight: .bold, design: .monospaced))
                    .foregroundStyle(self.shownColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                if self.isReadingMode {
                    // The hiragana is the subject; revealing the reading here
                    // would leak the answer, so keep the kanji hidden until the
                    // user judges, then reveal it as context.
                    if self.coord.spLocked, self.item.word.word != self.subject {
                        Text(self.item.word.word)
                            .font(.tujiBody)
                            .foregroundStyle(.tujiInk3)
                    }
                    if self.coord.spLocked, !self.shownIsCorrect {
                        Text("正解 \(self.subject)")
                            .font(.tujiCaption)
                            .foregroundStyle(.tujiInk3)
                    }
                } else {
                    if let reading = self.item.word.reading,
                       !reading.isEmpty,
                       reading != self.shown
                    {
                        Text(reading)
                            .font(.tujiBody)
                            .foregroundStyle(.tujiInk3)
                    }
                    if self.coord.spLocked, !self.shownIsCorrect {
                        Text("正解 \(self.item.word.word)")
                            .font(.tujiCaption)
                            .foregroundStyle(.tujiInk3)
                    }
                }
                if self.settings.current.showZh {
                    Text(self.item.word.chinese)
                        .font(.tujiCaption)
                        .foregroundStyle(.tujiInk3)
                }
            }
            .padding(.horizontal, Space.s4)
            .padding(.bottom, Space.s4)
        }
        .background(.tujiCard, in: .rect(cornerRadius: Radius.xl))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.xl)
                .stroke(.tujiInk4.opacity(0.15), lineWidth: 1)
        )
    }

    private var shownColor: Color {
        guard self.coord.spLocked else { return .tujiInk }
        return self.shownIsCorrect ? .tujiGreen : .tujiCoral
    }

    private var hero: some View {
        ZStack {
            Rectangle().fill(.tujiCard)
            LazyImage(url: self.item.word.imageURL) { state in
                if let image = state.image {
                    image.resizable()
                        .aspectRatio(contentMode: .fit)
                        .padding(Space.s2)
                } else if state.error != nil {
                    Image(systemName: "photo")
                        .font(.system(size: 28))
                        .foregroundStyle(.tujiInk4)
                } else {
                    ProgressView().tint(.tujiTeal)
                }
            }
            .pipeline(.shared)
        }
        .frame(height: 188)
        .clipped()
        .clipShape(.rect(topLeadingRadius: Radius.xl, topTrailingRadius: Radius.xl))
    }

    private var buttons: some View {
        HStack(spacing: Space.s3) {
            self.judge(say: .no, label: "錯", icon: "xmark", color: .tujiCoral)
            self.judge(say: .yes, label: "對", icon: "checkmark", color: .tujiGreen)
        }
        .animation(.easeOut(duration: 0.2), value: self.coord.spLocked)
    }

    private func judge(say: JudgeAnswer, label: LocalizedStringKey, icon: String, color: Color) -> some View {
        let style = self.judgeStyle(say: say, baseColor: color, baseIcon: icon)
        return Button {
            self.coord.spellJudge(shown: self.shown, says: say)
        } label: {
            HStack(spacing: Space.s2) {
                Image(systemName: style.icon)
                Text(label)
            }
            .font(.system(size: 18, weight: .heavy))
            .foregroundStyle(style.fg)
            .frame(maxWidth: .infinity)
            .padding(.vertical, Space.s4)
            .background(style.bg, in: .rect(cornerRadius: Radius.lg))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.lg)
                    .stroke(style.border, lineWidth: 2)
            )
            .opacity(style.opacity)
        }
        .buttonStyle(.plain)
        .disabled(self.coord.spLocked)
    }

    private struct JudgeStyle {
        var bg: Color
        var border: Color
        var fg: Color
        var icon: String
        var opacity: Double
    }

    /// After judging, colour each button by *whether the judgment was right*
    /// (not by the button's own identity), mirroring IdentifyView so Part 3 is
    /// as legible as Part 2:
    ///   • picked + correct → solid green ✓   • picked + wrong → solid coral ✗
    ///   • the right answer (when missed) → green outline   • else → dimmed
    private func judgeStyle(say: JudgeAnswer, baseColor: Color, baseIcon: String) -> JudgeStyle {
        guard self.judged else {
            // Resting affordance: each button in its own identity colour.
            return JudgeStyle(
                bg: baseColor.opacity(0.12), border: baseColor,
                fg: baseColor, icon: baseIcon, opacity: 1
            )
        }
        let picked = self.coord.spJudge == say
        let isCorrectChoice = say == self.correctSay
        if picked, isCorrectChoice {
            return JudgeStyle(
                bg: .tujiGreen, border: .tujiGreen,
                fg: .white, icon: "checkmark.circle.fill", opacity: 1
            )
        }
        if picked, !isCorrectChoice {
            return JudgeStyle(
                bg: .tujiCoral, border: .tujiCoral,
                fg: .white, icon: "xmark.circle.fill", opacity: 1
            )
        }
        if isCorrectChoice {
            // The answer the user should have tapped — highlight so they learn it.
            return JudgeStyle(
                bg: .tujiGreen.opacity(0.12), border: .tujiGreen,
                fg: .tujiGreen, icon: baseIcon, opacity: 1
            )
        }
        return JudgeStyle(
            bg: .tujiCard, border: .tujiInk4.opacity(0.15),
            fg: .tujiInk3, icon: baseIcon, opacity: 0.5
        )
    }
}
