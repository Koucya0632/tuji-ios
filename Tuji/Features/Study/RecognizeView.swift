// Step 1 of NewFlow: present the word + image + audio and ask whether
// the user already knows it. All three buttons write SRS (the only step
// that does): "第一次見" = .again, "有點印象" = .hard, "已經認識" = .good.
// Three options because this is the *new words* flow — not knowing the
// word is the expected answer, so it must have a button (the old 知道/熟悉
// pair were both positive and left first-timers guessing).

import Nuke
import NukeUI
import SwiftUI

struct RecognizeView: View {
    let coord: NewFlowCoordinator
    let item: StudyQueueItem

    @Environment(SettingsStore.self) private var settings
    @Environment(WordsStore.self) private var words

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
                        .lineLimit(2)
                        .minimumScaleFactor(0.6)
                    Spacer()
                    PronunciationButton(
                        text: self.item.word.word,
                        audioUrls: self.words.find(id: self.item.word.id)?.audioUrls,
                        size: 44
                    )
                }
                if !self.item.word.pronunciation.isEmpty {
                    Text(self.item.word.pronunciation)
                        .font(.tujiMono)
                        .foregroundStyle(.tujiInk3)
                }
                if let reading = self.item.word.reading,
                   !reading.isEmpty,
                   reading != self.item.word.pronunciation
                {
                    Text(reading)
                        .font(.tujiBody)
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
            Rectangle().fill(.tujiBg)
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
        VStack(spacing: Space.s2) {
            Text("這個字你認識嗎？")
                .font(.tujiCaption)
                .foregroundStyle(.tujiInk3)
            HStack(spacing: Space.s3) {
                BBtn(
                    title: "沒見過",
                    bg: .tujiCoral.opacity(0.12),
                    fg: .tujiCoral,
                    fullWidth: true,
                    action: { self.rate(.again) }
                )
                .disabled(self.coord.recLocked)
                BBtn(
                    title: "有印象",
                    bg: .tujiTealSoft,
                    fg: .tujiTeal,
                    fullWidth: true,
                    action: { self.rate(.hard) }
                )
                .disabled(self.coord.recLocked)
                BBtn(
                    title: "已認識",
                    bg: .tujiInk,
                    fg: .white,
                    fullWidth: true,
                    action: { self.rate(.good) }
                )
                .disabled(self.coord.recLocked)
            }
        }
    }

    private func rate(_ r: SRSRating) {
        Task { await self.coord.recognizeAnswer(rating: r) }
    }
}
