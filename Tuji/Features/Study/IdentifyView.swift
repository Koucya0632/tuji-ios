// Step 2 of NewFlow: show image + chinese chip; user taps the matching
// English. Pure practice — wrong answers requeue without writing SRS.

import Nuke
import NukeUI
import SwiftUI

struct IdentifyView: View {
    let coord: NewFlowCoordinator
    let item: StudyQueueItem

    private static let abc = ["A", "B", "C", "D", "E"]
    @Environment(SettingsStore.self) private var settings
    @Environment(WordsStore.self) private var words

    var body: some View {
        VStack(spacing: Space.s4) {
            self.bubble
            self.hero
            self.choicesList
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Space.s6)
        .padding(.bottom, Space.s5)
    }

    private var bubble: some View {
        MascotSpeechBubble(
            pose: .think,
            text: self.settings.current.learningDirection == .zhJa
                ? "對應的日文是哪個？"
                : "對應的英文是哪個？"
        )
    }

    private var hero: some View {
        ZStack(alignment: .bottomLeading) {
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
            .frame(height: 158)
            .clipped()
            .clipShape(.rect(cornerRadius: Radius.lg))

            HStack {
                Text(self.item.word.chinese)
                    .font(.system(size: 14, weight: .heavy))
                    .foregroundStyle(.tujiInk)
                    .padding(.horizontal, Space.s3)
                    .padding(.vertical, 6)
                    .background(.tujiBg, in: .capsule)
                Spacer()
                PronunciationButton(
                    text: self.item.word.word,
                    audioUrls: self.words.find(id: self.item.word.id)?.audioUrls,
                    size: 36
                )
            }
            .padding(Space.s3)
        }
    }

    private var choicesList: some View {
        VStack(spacing: Space.s2) {
            let choices = self.computedChoices
            ForEach(Array(choices.enumerated()), id: \.element) { idx, choice in
                self.optionRow(label: choice, letter: Self.abc[idx])
            }
        }
    }

    private var computedChoices: [String] {
        if let c = item.choices, !c.isEmpty { return c }
        // Fallback when backend didn't attach: surface just the answer
        // alongside placeholder dashes so the layout doesn't collapse.
        return [self.item.word.word]
    }

    private func optionRow(label: String, letter: String) -> some View {
        let state = self.optionState(for: label)
        return Button {
            self.coord.identifyPick(label)
        } label: {
            HStack(spacing: Space.s3) {
                Text(letter)
                    .font(.system(size: 13, weight: .heavy))
                    .foregroundStyle(state.letterFg)
                    .frame(width: 24, height: 24)
                    .background(state.letterBg, in: .circle)
                Text(label)
                    .font(.system(size: 16, weight: .heavy))
                    .foregroundStyle(state.fg)
                Spacer()
                if let icon = state.icon {
                    Image(systemName: icon)
                        .foregroundStyle(state.iconColor)
                }
            }
            .padding(.horizontal, Space.s4)
            .padding(.vertical, Space.s3)
            .background(state.bg, in: .rect(cornerRadius: Radius.lg))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.lg)
                    .stroke(state.border, lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
        .disabled(self.coord.idLocked)
        .opacity(state.opacity)
    }

    private func optionState(for label: String) -> OptStyle {
        guard let picked = coord.idPicked, self.coord.idLocked else {
            return OptStyle.idle
        }
        let isAnswer = label == self.item.word.word
        let isPicked = label == picked
        if isPicked, isAnswer { return .right }
        if isPicked, !isAnswer { return .wrong }
        if isAnswer { return .answer }
        return .dim
    }

    private struct OptStyle {
        let bg: Color
        let border: Color
        let fg: Color
        let letterFg: Color
        let letterBg: Color
        let icon: String?
        let iconColor: Color
        let opacity: Double

        static let idle = OptStyle(
            bg: .tujiCard, border: .tujiInk4.opacity(0.25),
            fg: .tujiInk, letterFg: .tujiInk3, letterBg: .tujiTealSoft,
            icon: nil, iconColor: .clear, opacity: 1
        )
        static let right = OptStyle(
            bg: .tujiGreen.opacity(0.12), border: .tujiGreen,
            fg: .tujiInk, letterFg: .white, letterBg: .tujiGreen,
            icon: "checkmark.circle.fill", iconColor: .tujiGreen, opacity: 1
        )
        static let wrong = OptStyle(
            bg: .tujiCoral.opacity(0.12), border: .tujiCoral,
            fg: .tujiInk, letterFg: .white, letterBg: .tujiCoral,
            icon: "xmark.circle.fill", iconColor: .tujiCoral, opacity: 1
        )
        static let answer = OptStyle(
            bg: .tujiGreen.opacity(0.08), border: .tujiGreen.opacity(0.7),
            fg: .tujiInk, letterFg: .white, letterBg: .tujiGreen,
            icon: "arrow.left.circle.fill", iconColor: .tujiGreen, opacity: 1
        )
        static let dim = OptStyle(
            bg: .tujiCard, border: .tujiInk4.opacity(0.15),
            fg: .tujiInk3, letterFg: .tujiInk4, letterBg: .tujiInk4.opacity(0.15),
            icon: nil, iconColor: .clear, opacity: 0.5
        )
    }
}
