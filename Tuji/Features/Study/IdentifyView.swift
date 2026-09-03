// Step 2 of NewFlow: show image + chinese chip; user taps the matching
// English. Pure practice — wrong answers requeue without writing SRS.

import SwiftUI

struct IdentifyView: View {
    let coord: NewFlowCoordinator
    let item: StudyQueueItem

    @Environment(SettingsStore.self) private var settings
    @Environment(WordsStore.self) private var words
    @Environment(\.targetLanguage) private var session

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
        let language = self.item.word.language(in: self.session)
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
                    WordPicture(
                        url: self.item.word.imageURL,
                        kind: self.item.word.imageKind,
                        glyphSize: 28
                    )
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
                    subject: SpokenWord(self.item.word),
                    size: 48,
                    ground: .tujiPaper
                )
            }
            .padding(Space.s3)
        }
    }

    private var choicesList: some View {
        StudyChoiceList(
            item: self.item,
            variant: self.coord.choicesVariant(for: self.item),
            picked: self.coord.idPicked,
            revealed: self.coord.idLocked
        ) { self.coord.identifyPick($0) }
    }
}
