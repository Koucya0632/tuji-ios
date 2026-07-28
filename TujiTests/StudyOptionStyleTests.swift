// Pins StudyOptionStyle.forOption — the right/wrong/answer/dim reveal logic the
// 選字 and 複習 MCQ surfaces used to duplicate. Structs aren't Equatable, so the
// distinct cases are told apart by their icon + opacity.

import Testing
@testable import Tuji

@MainActor
struct StudyOptionStyleTests {
    @Test
    func beforeRevealEveryOptionIsIdle() {
        let s = StudyOptionStyle.forOption(label: "a", answer: "a", picked: nil, revealed: false)
        #expect(s.icon == nil)
        #expect(s.opacity == 1)
    }

    @Test
    func revealClassifiesEachOption() {
        // Picked the right answer → right (check).
        #expect(StudyOptionStyle.forOption(label: "a", answer: "a", picked: "a", revealed: true).icon
            == "checkmark.circle.fill")
        // Picked a wrong answer → wrong (x).
        #expect(StudyOptionStyle.forOption(label: "b", answer: "a", picked: "b", revealed: true).icon
            == "xmark.circle.fill")
        // The answer, not the one picked → answer (arrow).
        #expect(StudyOptionStyle.forOption(label: "a", answer: "a", picked: "b", revealed: true).icon
            == "arrow.left.circle.fill")
        // An unrelated option → dim (no icon, faded).
        let dim = StudyOptionStyle.forOption(label: "c", answer: "a", picked: "b", revealed: true)
        #expect(dim.icon == nil)
        #expect(dim.opacity == 0.5)
    }
}
