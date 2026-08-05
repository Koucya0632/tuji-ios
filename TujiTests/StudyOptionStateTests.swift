// Pins StudyOptionState.forOption — the right/wrong/answer/dim reveal logic the
// 選字 and 複習 MCQ surfaces used to duplicate.
//
// The cases used to be told apart by which SF Symbol they carried, because the
// styles were a struct with no identity of its own. They now *are* the identity,
// so the assertions name the case instead of a checkmark that no longer exists.

import Testing
@testable import Tuji

@MainActor
struct StudyOptionStateTests {
    @Test
    func beforeRevealEveryOptionIsIdle() {
        #expect(StudyOptionState.forOption(label: "a", answer: "a", picked: nil, revealed: false) == .idle)
        // Revealed but nothing picked can't happen through the flow; if it does,
        // fall back to idle rather than lighting up an answer nobody chose.
        #expect(StudyOptionState.forOption(label: "a", answer: "a", picked: nil, revealed: true) == .idle)
    }

    @Test
    func revealClassifiesEachOption() {
        #expect(StudyOptionState.forOption(label: "a", answer: "a", picked: "a", revealed: true) == .right)
        #expect(StudyOptionState.forOption(label: "b", answer: "a", picked: "b", revealed: true) == .wrong)
        #expect(StudyOptionState.forOption(label: "a", answer: "a", picked: "b", revealed: true) == .answer)
        #expect(StudyOptionState.forOption(label: "c", answer: "a", picked: "b", revealed: true) == .dim)
    }

    @Test
    func onlyTheRightAndTheAnswerInvertToInk() {
        #expect(StudyOptionState.right.ground == .tujiInk)
        #expect(StudyOptionState.answer.ground == .tujiInk)
        // A wrong pick keeps its ground and takes an edge instead.
        #expect(StudyOptionState.wrong.ground == .tujiPaper2)
        #expect(StudyOptionState.wrong.leadingEdge == .tujiAlert)
        #expect(StudyOptionState.idle.leadingEdge == nil)
    }
}
