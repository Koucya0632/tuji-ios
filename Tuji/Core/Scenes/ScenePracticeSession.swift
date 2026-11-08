// One pass through a 場面: the planned steps, and where the current 問句 is.
//
// A 問句 is presenting → answered wrong (replay and try again, as often as it
// takes) → revealed (meaning, 回應 and its audio) → the next one. Progress is
// written at the reveal, not at "next", so quitting on the reveal does not
// make the 問句 owed again. The cursor is written as each 問句 is shown, so
// quitting before the reveal reopens that same 問句.

import Foundation
import Observation

@MainActor
@Observable
final class ScenePracticeSession {
    enum QuestionPhase: Equatable {
        case presenting
        case answeredWrong(tried: Set<String>)
        case revealed(firstTry: Bool)
    }

    enum Phase: Equatable {
        case practising(step: Int, QuestionPhase)
        case finished(Summary)
    }

    struct Summary: Equatable {
        let practised: Int
        let firstTry: Int
        /// The scene's standing after this pass, for the 明天複習 line.
        let status: SceneStatus
    }

    let scene: PracticeScene
    let steps: [PracticeStep]
    private(set) var phase: Phase

    @ObservationIgnored private let store: SceneProgressStore
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private let calendar: Calendar
    @ObservationIgnored private var firstTryCount = 0

    init(
        scene: PracticeScene,
        store: SceneProgressStore,
        now: @escaping () -> Date = Date.init,
        calendar: Calendar = .current
    ) {
        self.scene = scene
        self.store = store
        self.now = now
        self.calendar = calendar
        let today = LocalDay(now(), calendar: calendar)
        self.steps = ScenePractice.plan(scene, book: store.book, today: today)
        self.phase = .finished(Summary(practised: 0, firstTry: 0, status: ScenePractice.status(scene, book: store.book, today: today)))
        if !self.steps.isEmpty { self.show(0) }
    }

    var currentStep: PracticeStep? {
        guard case let .practising(index, _) = self.phase else { return nil }
        return self.steps[index]
    }

    var currentQuestion: SceneQuestion? {
        self.currentStep.map { self.scene.questions[$0.questionIndex] }
    }

    /// 1-based position for the progress line.
    var position: (current: Int, total: Int)? {
        guard case let .practising(index, _) = self.phase else { return nil }
        return (index + 1, self.steps.count)
    }

    func answer(_ choiceId: String) {
        guard case let .practising(index, questionPhase) = self.phase,
              let question = self.currentQuestion,
              let choice = question.choices.first(where: { $0.id == choiceId })
        else { return }
        let tried: Set<String>
        switch questionPhase {
        case .presenting: tried = []
        case let .answeredWrong(previous): tried = previous
        case .revealed: return
        }
        guard choice.correct else {
            self.phase = .practising(step: index, .answeredWrong(tried: tried.union([choiceId])))
            return
        }
        let firstTry = tried.isEmpty
        if firstTry { self.firstTryCount += 1 }
        self.phase = .practising(step: index, .revealed(firstTry: firstTry))
        self.record(self.steps[index], question: question, nextStep: index + 1)
    }

    func next() {
        guard case let .practising(index, .revealed) = self.phase else { return }
        if index + 1 < self.steps.count {
            self.show(index + 1)
        } else {
            self.store.update { $0.cursors[self.scene.id] = nil }
            let today = LocalDay(self.now(), calendar: self.calendar)
            self.phase = .finished(Summary(
                practised: self.steps.count,
                firstTry: self.firstTryCount,
                status: ScenePractice.status(self.scene, book: self.store.book, today: today)
            ))
        }
    }

    private func show(_ index: Int) {
        self.phase = .practising(step: index, .presenting)
        let questionIndex = self.steps[index].questionIndex
        self.store.update { $0.cursors[self.scene.id] = questionIndex }
    }

    private func record(_ step: PracticeStep, question: SceneQuestion, nextStep: Int) {
        let today = LocalDay(self.now(), calendar: self.calendar)
        let following = nextStep < self.steps.count ? self.steps[nextStep].questionIndex : nil
        self.store.update { book in
            book.questions[question.id] = ScenePractice.completing(
                book.progress(question.id),
                step: step,
                today: today,
                calendar: self.calendar
            )
            book.cursors[self.scene.id] = following
        }
    }
}
