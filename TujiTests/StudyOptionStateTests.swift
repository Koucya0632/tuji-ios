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
        // A wrong pick keeps its ground and takes a frame instead.
        #expect(StudyOptionState.wrong.ground == .tujiPaper2)
    }

    /// The ground says which one is the answer; the frame says which one was
    /// tapped. `.answer` is the case that separates them — it is the answer the
    /// user did *not* pick, so it gets the ink ground and no frame.
    @Test
    func theFrameNamesThePickAndTheGroundNamesTheAnswer() {
        #expect(StudyOptionState.right.border == .tujiAccumulation)
        #expect(StudyOptionState.wrong.border == .tujiAlert)
        #expect(StudyOptionState.answer.border == nil)
        #expect(StudyOptionState.idle.border == nil)
        #expect(StudyOptionState.dim.border == nil)
    }

    /// 複習's 看圖選字 marks a wrong pick and leaves the question open, so this
    /// state has to exist *before* anything is revealed — and survive the
    /// reveal, rather than dimming into the options nobody touched.
    @Test
    func aRuledOutOptionIsWrongBeforeAndAfterTheReveal() {
        #expect(
            StudyOptionState.forOption(
                label: "b", answer: "a", picked: nil, revealed: false, wrongPicks: ["b"]
            ) == .wrong
        )
        #expect(
            StudyOptionState.forOption(
                label: "b", answer: "a", picked: "a", revealed: true, wrongPicks: ["b"]
            ) == .wrong
        )
        // The pick that landed is still the right one, and the option nobody
        // ruled out still recedes.
        #expect(
            StudyOptionState.forOption(
                label: "a", answer: "a", picked: "a", revealed: true, wrongPicks: ["b"]
            ) == .right
        )
        #expect(
            StudyOptionState.forOption(
                label: "c", answer: "a", picked: "a", revealed: true, wrongPicks: ["b"]
            ) == .dim
        )
        // Untouched options stay live while the question is open.
        #expect(
            StudyOptionState.forOption(
                label: "c", answer: "a", picked: nil, revealed: false, wrongPicks: ["b"]
            ) == .idle
        )
    }
}
