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
            self.prompt
                .padding(.horizontal, Space.s4)
            self.hero
            self.choicesList
                .padding(.horizontal, Space.s4)
            Spacer(minLength: 0)
        }
        .padding(.bottom, Space.s4)
    }

    /// A line, not a character. The cat used to sit here on every card with its
    /// pose switching to cheer after three in a row — C.11 allows it at four
    /// moments, and "every question" is not one. The words themselves stay: on
    /// a JA card the options are Japanese and on an EN card they are English,
    /// so which language is being asked for is information, not chatter.
    private var prompt: some View {
        // The quizzed word's own language, so a JA custom word asks 日文 even
        // if the session direction disagrees; untagged words follow the session.
        let language = self.item.word.wordLanguage
            ?? self.settings.current.learningDirection.targetLanguage
        return Text(
            language == .ja
                ? LocalizedStringKey("對應的日文是哪個？")
                : LocalizedStringKey("對應的英文是哪個？")
        )
        .font(.tujiLabel)
        .tracking(0.5)
        .foregroundStyle(.tujiInk3)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var hero: some View {
        ZStack(alignment: .bottomLeading) {
            Color.tujiPaper2
                .frame(height: 200)
                .overlay {
                    LazyImage(url: self.item.word.imageURL) { state in
                        if let image = state.image {
                            image.resizable()
                                .aspectRatio(
                                    contentMode: self.item.word.imageKind == .cutout ? .fit : .fill
                                )
                                .padding(self.item.word.imageKind == .cutout ? Space.s3 : 0)
                                .blendMode(
                                    self.item.word.imageKind == .cutout ? .multiply : .normal
                                )
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
                .clipped()

            HStack(alignment: .bottom) {
                if self.settings.current.showZh {
                    Text(self.item.word.chinese)
                        .font(.tujiBodySm)
                        .foregroundStyle(.tujiInk)
                        .lineLimit(2)
                        .padding(.horizontal, Space.s2)
                        .padding(.vertical, Space.s1)
                        .background(.tujiPaper)
                }
                Spacer(minLength: Space.s2)
                PronunciationButton(
                    text: self.item.word.word,
                    language: self.item.word.wordLanguage,
                    audioUrls: self.words.find(id: self.item.word.id)?.audioUrls,
                    size: 48,
                    ground: .tujiPaper
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
