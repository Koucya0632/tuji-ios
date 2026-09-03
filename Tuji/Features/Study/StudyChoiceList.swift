// The four MCQ options, for both study surfaces.
//
// 選字 (IdentifyView) and 複習 (ReviewFlowView) each carried their own copy of
// this: the same `A/B/C/D` letters, the same 18-line `ForEach` over
// `StudyOptionRow`, the same `computedChoices` assembling the same four
// arguments out of the same three environment reads, under a doc comment that
// was ~90% the same text. The extraction stopped at the row; the assembly
// around it was pasted.

import SwiftUI

struct StudyChoiceList: View {
    let item: StudyQueueItem
    /// Bumps when the word leaves the screen (複習) or per wrong attempt
    /// (學新字), so a re-test reshuffles instead of letting 「the answer was C」
    /// stand in for the word.
    let variant: Int
    /// nil ⇒ nothing picked yet.
    let picked: String?
    /// Locked: the answer is showing and the rows stop responding.
    let revealed: Bool
    /// Options ruled out this presentation: 複習's 看圖選字 marks a wrong pick
    /// and leaves the question open, so those rows go dead while the rest stay
    /// live. Empty for 學新字, whose first pick ends the question either way.
    var wrongPicks: Set<String> = []
    let onPick: (String) -> Void

    @Environment(WordsStore.self) private var words
    @Environment(\.targetLanguage) private var session

    private static let letters = ["A", "B", "C", "D", "E"]

    var body: some View {
        VStack(spacing: Space.s2) {
            let choices = self.choices
            ForEach(Array(choices.enumerated()), id: \.element) { idx, choice in
                StudyOptionRow(
                    letter: Self.letters[idx],
                    label: choice,
                    state: StudyOptionState.forOption(
                        label: choice,
                        answer: self.item.word.word,
                        picked: self.picked,
                        revealed: self.revealed,
                        wrongPicks: self.wrongPicks
                    ),
                    disabled: self.revealed || self.wrongPicks.contains(choice)
                ) { self.onPick(choice) }
            }
        }
    }

    /// Server choices scrubbed of near-synonyms of the answer + topped up;
    /// custom (自制圖鑑) cards build the whole set from the local pool.
    private var choices: [String] {
        studyChoices(
            for: self.item,
            pool: self.words.words,
            session: self.session,
            variant: self.variant
        )
    }
}
