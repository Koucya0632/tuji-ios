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

    private var shownIsCorrect: Bool {
        self.shown == self.item.word.word
    }

    private var bubble: some View {
        HStack(spacing: Space.s2) {
            Mascot(pose: .think, size: 40)
            Text("這個字拼對了嗎？")
                .font(.system(size: 14, weight: .heavy))
                .foregroundStyle(.tujiInk)
                .padding(.horizontal, Space.s3)
                .padding(.vertical, Space.s2)
                .background(.tujiTealSoft, in: .rect(cornerRadius: Radius.md))
            Spacer()
        }
    }

    private var card: some View {
        VStack(spacing: Space.s4) {
            self.hero
            VStack(spacing: Space.s2) {
                Text(self.shown)
                    .font(.tujiMono)
                    .foregroundStyle(self.shownColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                if self.coord.spLocked, !self.shownIsCorrect {
                    Text("正解 \(self.item.word.word)")
                        .font(.tujiCaption)
                        .foregroundStyle(.tujiInk3)
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
    }

    private func judge(say: JudgeAnswer, label: String, icon: String, color: Color) -> some View {
        let selected = self.coord.spJudge == say
        return Button {
            self.coord.spellJudge(shown: self.shown, says: say)
        } label: {
            HStack(spacing: Space.s2) {
                Image(systemName: icon)
                Text(label)
            }
            .font(.system(size: 18, weight: .heavy))
            .foregroundStyle(selected ? .white : color)
            .frame(maxWidth: .infinity)
            .padding(.vertical, Space.s4)
            .background(selected ? color : color.opacity(0.12), in: .rect(cornerRadius: Radius.lg))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.lg)
                    .stroke(color, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
        .disabled(self.coord.spLocked)
    }
}
