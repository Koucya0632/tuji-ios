import Foundation
import Observation

/// Working through one saved practice set. Everything here is local: the set came
/// with its answers and reasons, so choosing, checking and redoing never ask the
/// model again and never spend points. Only 換一組題目 does, and that is the
/// conversation's job, not this one's.
@MainActor
@Observable
final class GrammarPracticeSession {
    enum Screen: Equatable {
        /// Before a run, or between runs: start, continue, or read the answers.
        case overview
        case question
        case summary
        /// Every question with its answer and reasons, without answering.
        case review
    }

    let practice: GrammarPractice
    private(set) var progress: GrammarPracticeProgress
    private(set) var screen: Screen
    /// The option picked but not yet confirmed. Confirming fixes it.
    var selection: String?
    private let setId: String
    private let owner: String
    private let learning: String
    private let store: GrammarProgressStoring

    init(
        practice: GrammarPractice,
        setId: String,
        owner: String,
        learning: String,
        store: GrammarProgressStoring = DefaultsGrammarProgress()
    ) {
        self.practice = practice
        self.setId = setId
        self.owner = owner
        self.learning = learning
        self.store = store
        let progress = store.progress(owner: owner, learning: learning, setId: setId)
        self.progress = progress
        // A finished run reopens on its results; anything else on the choice to go on.
        self.screen = progress.attempts.last?.finished == true ? .summary : .overview
    }

    var attempt: GrammarAttempt? {
        self.progress.attempts.last
    }

    /// The run in progress, if there is one.
    var unfinished: GrammarAttempt? {
        self.attempt.flatMap { $0.finished ? nil : $0 }
    }

    /// The question on screen: the first one in this run not yet answered, or the
    /// one just answered while its reasons are being read.
    private(set) var questionId: String?

    var question: GrammarPractice.Question? {
        self.questionId.flatMap { id in self.practice.questions.first { $0.id == id } }
    }

    /// 第 n／m 題 within the current run.
    var position: (index: Int, total: Int)? {
        guard let attempt = self.attempt, let id = self.questionId,
              let index = attempt.questionIds.firstIndex(of: id)
        else { return nil }
        return (index + 1, attempt.questionIds.count)
    }

    /// The confirmed answer for the question on screen, once there is one.
    var confirmed: String? {
        self.questionId.flatMap { self.attempt?.answers[$0] }
    }

    struct Score: Equatable {
        let correct: Int
        let answered: Int
        let total: Int
    }

    /// 首次作答: the first run, and only what was answered in it.
    var firstScore: Score? {
        guard let first = self.progress.attempts.first(where: \.isFirst) else { return nil }
        return Score(correct: self.correct(in: first), answered: first.answers.count, total: first.questionIds.count)
    }

    func correct(in attempt: GrammarAttempt) -> Int {
        attempt.questionIds.count(where: { self.isCorrect(attempt.answers[$0], question: $0) })
    }

    func wrong(in attempt: GrammarAttempt) -> [String] {
        attempt.questionIds.filter { id in
            attempt.answers[id].map { !self.isCorrect($0, question: id) } ?? false
        }
    }

    func isCorrect(_ option: String?, question id: String) -> Bool {
        guard let option, let question = self.practice.questions.first(where: { $0.id == id }) else { return false }
        return option == question.answer
    }

    /// 開始練習 / 繼續練習.
    func start() {
        if self.unfinished == nil {
            let first = !self.progress.attempts.contains(where: \.isFirst) && !self.progress.revealed
            self.begin(self.practice.questions.map(\.id), first: first)
        }
        self.moveToNextQuestion()
    }

    /// 重做錯題: the questions the last run got wrong. Free, and never the score.
    func redoWrong() {
        guard let attempt = self.attempt else { return }
        let wrong = self.wrong(in: attempt)
        guard !wrong.isEmpty else { return }
        self.begin(wrong, first: false)
        self.moveToNextQuestion()
    }

    /// 重做這組: every question again. Free, and never the score.
    func redoAll() {
        self.begin(self.practice.questions.map(\.id), first: false)
        self.moveToNextQuestion()
    }

    /// 查看題目與解析. Read before the first run is done, that run can no longer be the score.
    func review() {
        if !self.progress.attempts.contains(where: { $0.isFirst && $0.finished }) {
            self.progress.revealed = true
            // A first run cut short becomes practice: its answers were made before the key was read,
            // but the rest would not be.
            if let index = self.progress.attempts.lastIndex(where: { $0.isFirst && !$0.finished }) {
                let old = self.progress.attempts[index]
                self.progress.attempts[index] = GrammarAttempt(
                    id: old.id,
                    isFirst: false,
                    questionIds: old.questionIds,
                    answers: old.answers
                )
            }
            self.save()
        }
        self.screen = .review
    }

    /// Back from the answers, or from results, to the choice of what to do next.
    func showOverview() {
        self.screen = self.attempt?.finished == true ? .summary : .overview
    }

    func select(_ option: String) {
        guard self.confirmed == nil else { return }
        self.selection = option
    }

    /// 確認答案: fixes the choice and shows whether it was right, with every reason.
    func confirm() {
        guard let id = self.questionId, let option = self.selection, self.confirmed == nil,
              var attempt = self.attempt, !attempt.finished, attempt.answers[id] == nil
        else { return }
        attempt.answers[id] = option
        self.progress.attempts[self.progress.attempts.count - 1] = attempt
        self.save()
    }

    /// 下一題, or the results after the last one. Never automatic: the reasons
    /// stay until the person moves on.
    func next() {
        guard self.confirmed != nil else { return }
        self.moveToNextQuestion()
    }

    private func moveToNextQuestion() {
        self.selection = nil
        guard let attempt = self.attempt else { return }
        if let id = attempt.questionIds.first(where: { attempt.answers[$0] == nil }) {
            self.questionId = id
            self.screen = .question
        } else {
            self.questionId = nil
            self.screen = .summary
        }
    }

    private func begin(_ ids: [String], first: Bool) {
        self.progress.attempts.append(GrammarAttempt(
            id: UUID().uuidString.lowercased(),
            isFirst: first,
            questionIds: ids
        ))
        self.save()
    }

    private func save() {
        self.store.save(self.progress, owner: self.owner, learning: self.learning, setId: self.setId)
    }
}
