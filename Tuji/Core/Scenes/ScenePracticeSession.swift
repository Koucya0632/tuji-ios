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

    struct QuestionResult: Equatable, Identifiable {
        let question: SceneQuestion
        let wrongTries: Int
        var usedHint = false

        /// Worth another look on the summary: missed, or got with help.
        var needsAnotherLook: Bool {
            self.wrongTries > 0 || self.usedHint
        }

        var id: SceneQuestionID {
            self.question.id
        }
    }

    struct Summary: Equatable {
        /// The questions of this pass: those missed or helped first, then the
        /// rest, each group in the order they were asked.
        let results: [QuestionResult]
        /// The scene's standing after this pass, for the 明天複習 line.
        let status: SceneStatus
    }

    let scene: PracticeScene
    /// The trip this pass takes, on a staged scene.
    let route: StageRoute?
    let steps: [PracticeStep]
    private(set) var phase: Phase

    @ObservationIgnored private let store: SceneProgressStore
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private let calendar: Calendar
    @ObservationIgnored private var wrongTries: [Int: Int] = [:]
    @ObservationIgnored private var hinted: Set<Int> = []

    init(
        scene: PracticeScene,
        store: SceneProgressStore,
        route: StageRoute? = nil,
        now: @escaping () -> Date = Date.init,
        calendar: Calendar = .current
    ) {
        self.scene = scene
        self.store = store
        self.now = now
        self.calendar = calendar
        let today = LocalDay(now(), calendar: calendar)
        self.route = route ?? ScenePractice.suggestedRoute(scene, book: store.book, today: today)
        self.steps = ScenePractice.plan(scene, book: store.book, today: today, route: self.route)
        self.phase = .finished(Summary(
            results: [],
            status: ScenePractice.status(scene, book: store.book, today: today)
        ))
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
        guard let choice = self.currentQuestion?.choices.first(where: { $0.id == choiceId }) else { return }
        self.settle(tried: choiceId, correct: choice.correct)
    }

    /// A reply said on a staged listening 問句. One that does not fit this
    /// trip counts as a try; its result shows and the traveller tries again.
    func reply(_ reply: StageReply) {
        self.settle(tried: "reply:" + reply.id, correct: reply.fits)
    }

    /// A machine run to its end. Restarting a machine is the view's business;
    /// only a finish reaches the session, once.
    func finish(_ outcome: MachineOutcome, fits: Bool) {
        self.settle(tried: "machine:\(outcome)", correct: fits)
    }

    /// Slow playback, the subtitle, or 「請再說一次」 on the 問句 on screen.
    func noteHint() {
        guard case let .practising(index, phase) = self.phase, phase != .revealed(firstTry: true),
              phase != .revealed(firstTry: false)
        else { return }
        self.hinted.insert(index)
    }

    /// 「請再說一次」: another phrasing of the 問句 on screen, said the way
    /// staff would repeat it. It is marked heard, so tomorrow's review picks
    /// one not yet played. Nil when every other phrasing has been heard.
    func askAgain() -> SpokenLine? {
        guard let step = self.currentStep, let question = self.currentQuestion else { return nil }
        let heard = self.store.book.progress(question.id).usedPhrasingIds.union([step.phrasing.id])
        guard let phrasing = question.phrasings.first(where: { $0.spoken != nil && !heard.contains($0.id) }),
              let line = phrasing.spoken
        else { return nil }
        self.noteHint()
        self.store.update { book in
            book.questions[question.id, default: QuestionProgress()].usedPhrasingIds.insert(phrasing.id)
        }
        return line
    }

    private func settle(tried key: String, correct: Bool) {
        guard case let .practising(index, questionPhase) = self.phase,
              let question = self.currentQuestion
        else { return }
        let tried: Set<String>
        switch questionPhase {
        case .presenting: tried = []
        case let .answeredWrong(previous): tried = previous
        case .revealed: return
        }
        guard correct else {
            self.wrongTries[index, default: 0] += 1
            self.phase = .practising(step: index, .answeredWrong(tried: tried.union([key])))
            return
        }
        self.phase = .practising(step: index, .revealed(firstTry: tried.isEmpty))
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
                results: {
                    let all = self.steps.indices.map { index in
                        QuestionResult(
                            question: self.scene.questions[self.steps[index].questionIndex],
                            wrongTries: self.wrongTries[index] ?? 0,
                            usedHint: self.hinted.contains(index)
                        )
                    }
                    return all.filter(\.needsAnotherLook) + all.filter { !$0.needsAnotherLook }
                }(),
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
            book.lastSceneId = self.scene.id
        }
    }
}

extension SceneQuestion {
    /// The choices in the order one phrasing shows them. Content lists the
    /// correct one first more often than not.
    nonisolated func choices(for phrasing: PhrasingID) -> [SceneChoice] {
        mixed(self.choices, by: phrasing) { $0.id }
    }
}

extension StageStep {
    /// The replies in the order one phrasing shows them. Content lists one
    /// that fits first.
    nonisolated func replies(for phrasing: PhrasingID) -> [StageReply] {
        mixed(self.replies ?? [], by: phrasing) { $0.id }
    }
}

/// `items` in an order fixed by the phrasing: stable while that phrasing is on
/// screen, different from one 問法 to the next. FNV-1a then a splitmix64
/// finish, because `Hasher` is seeded per launch and FNV alone barely mixes
/// the last byte, which is often all that tells two ids apart.
nonisolated func mixed<Item>(_ items: [Item], by phrasing: PhrasingID, id: (Item) -> String) -> [Item] {
    func rank(_ item: Item) -> UInt64 {
        var z = (phrasing.rawValue + "|" + id(item)).utf8.reduce(14_695_981_039_346_656_037) { hash, byte in
            (hash ^ UInt64(byte)) &* 1_099_511_628_211
        }
        z &+= 0x9E3779B97F4A7C15
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
    return items.sorted { rank($0) < rank($1) }
}
