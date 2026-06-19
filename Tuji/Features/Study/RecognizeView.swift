// Step 1 of NewFlow: present the word + image + audio and ask whether
// the user already knows it. Both buttons write SRS (the only step that
// does); "知道" = .hard, "熟悉" = .good.

import Nuke
import NukeUI
import SwiftUI

struct RecognizeView: View {
    let coord: NewFlowCoordinator
    let item: StudyQueueItem

    @Environment(SettingsStore.self) private var settings

    var body: some View {
        VStack(spacing: Space.s4) {
            self.card
            Spacer(minLength: 0)
            self.buttons
        }
        .padding(.horizontal, Space.s6)
        .padding(.bottom, Space.s5)
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            self.hero
            VStack(alignment: .leading, spacing: Space.s2) {
                HStack(alignment: .firstTextBaseline) {
                    Text(self.item.word.word)
                        .font(.tujiH1)
                        .foregroundStyle(.tujiInk)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    Spacer()
                    PronunciationButton(text: self.item.word.word, size: 44)
                }
                if !self.item.word.pronunciation.isEmpty {
                    Text(self.item.word.pronunciation)
                        .font(.tujiMono)
                        .foregroundStyle(.tujiInk3)
                }
                if self.settings.current.showZh {
                    Text(self.item.word.chinese)
                        .font(.tujiBody)
                        .foregroundStyle(.tujiInk2)
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
                        .font(.system(size: 32))
                        .foregroundStyle(.tujiInk4)
                } else {
                    ProgressView().tint(.tujiTeal)
                }
            }
            .pipeline(.shared)
        }
        .frame(height: 230)
        .clipped()
        .clipShape(.rect(topLeadingRadius: Radius.xl, topTrailingRadius: Radius.xl))
    }

    private var buttons: some View {
        HStack(spacing: Space.s3) {
            BBtn(
                title: "知道",
                bg: .tujiTealSoft,
                fg: .tujiTeal,
                fullWidth: true,
                action: { self.rate(.hard) }
            )
            .disabled(self.coord.recLocked)
            BBtn(
                title: "熟悉",
                bg: .tujiInk,
                fg: .white,
                fullWidth: true,
                action: { self.rate(.good) }
            )
            .disabled(self.coord.recLocked)
        }
    }

    private func rate(_ r: SRSRating) {
        Task { await self.coord.recognizeAnswer(rating: r) }
    }
}
