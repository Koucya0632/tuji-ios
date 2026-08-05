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
        VStack(spacing: Space.s3) {
            self.bubble
            self.hero
            self.choicesList
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Space.s4)
        .padding(.bottom, Space.s4)
    }

    private var bubble: some View {
        // 3+ consecutive correct answers put the mascot in cheer — a small
        // momentum reward wired straight to existing art.
        // The quizzed word's own language, so a JA custom word asks 日文 even
        // if the session direction disagrees; untagged words follow the session.
        let language = self.item.word.wordLanguage
            ?? self.settings.current.learningDirection.targetLanguage
        return MascotSpeechBubble(
            pose: self.coord.combo >= 3 ? .cheer : .think,
            text: language == .ja ? "對應的日文是哪個？" : "對應的英文是哪個？"
        )
    }

    private var hero: some View {
        ZStack(alignment: .bottomLeading) {
            ZStack {
                Rectangle().fill(.tujiPaper)
                LazyImage(url: self.item.word.imageURL) { state in
                    if let image = state.image {
                        image.resizable()
                            .aspectRatio(contentMode: .fit)
                            .padding(Space.s2)
                    } else if state.error != nil {
                        Image(systemName: "photo")
                            .font(.system(size: 28))
                            .foregroundStyle(.tujiInk3)
                    } else {
                        TujiImagePlaceholder()
                    }
                }
                .pipeline(.shared)
            }
            .frame(height: 158)
            .clipped()
            .clipShape(.rect(cornerRadius: Radius.r0))

            HStack {
                Text(self.item.word.chinese)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.tujiInk)
                    .padding(.horizontal, Space.s3)
                    .padding(.vertical, 6)
                    .background(.tujiPaper, in: .rect(cornerRadius: Radius.r0))
                Spacer()
                PronunciationButton(
                    text: self.item.word.word,
                    language: self.item.word.wordLanguage,
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
                StudyOptionRow(
                    letter: Self.abc[idx],
                    label: choice,
                    state: StudyOptionState.forOption(
                        label: choice,
                        answer: self.item.word.word,
                        picked: self.coord.idPicked,
                        revealed: self.coord.idLocked
                    ),
                    disabled: self.coord.idLocked
                ) { self.coord.identifyPick(choice) }
            }
        }
    }

    private var computedChoices: [String] {
        // Server choices scrubbed of near-synonyms of the answer + topped up;
        // custom (自制圖鑑) cards build the whole set from the local pool.
        // The variant bumps per wrong attempt so a retry reshuffles.
        studyChoices(
            for: self.item,
            pool: self.words.words,
            variant: self.coord.choicesVariant(for: self.item)
        )
    }
}
