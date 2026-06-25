// State machine for the "learn new words" three-step micro lesson
// (§III.P). Step 1 Recognize captures the SRS rating but defers the write;
// the POST /api/study/answer fires per word when it clears Step 3 Spell, so
// `今日目標` (todayNew = user_cards created today) counts only words that
// completed all 3 parts. Step 2 Identify (MCQ) and Step 3 Spell are pure
// practice — wrong answers re-queue, no extra backend write. A word abandoned
// before clearing Spell is never written (no SRS row, no goal credit).

import OSLog
import Observation
import SwiftUI

enum NewFlowStep: Int, Hashable {
    case recognize = 1
    case identify = 2
    case spell = 3
    case done = 4
}

enum JudgeAnswer: Hashable {
    case yes, no
}

@MainActor
@Observable
final class NewFlowCoordinator {
    let queue: [StudyQueueItem]
    var step: NewFlowStep = .recognize

    // Step 1 — Recognize (linear sweep through queue)
    var recIdx: Int = 0
    var recRating: SRSRating?
    var recLocked: Bool = false

    // Step 2 — Identify (MCQ, requeue on wrong)
    var idQueue: [StudyQueueItem]
    var idDone: Int = 0
    var idPicked: String?
    var idLocked: Bool = false

    // Step 3 — Spell (correct/incorrect judge, requeue on wrong)
    var spQueue: [StudyQueueItem]
    var spDone: Int = 0
    var spAttempt: Int = 0
    var spJudge: JudgeAnswer?
    var spLocked: Bool = false

    /// Surface to NewFlowView so it can present WordPeek for wrong answers.
    var peek: StudyQueueWord?

    /// Recognize-step ratings held back until the word clears Step 3 Spell —
    /// keyed by card id. See commitLearned(_:).
    private var pendingRatings: [Int: SRSRating] = [:]

    private let log = Logger(subsystem: "app.tuji.ios", category: "new-flow")

    init(queue: [StudyQueueItem]) {
        self.queue = queue
        self.idQueue = queue
        self.spQueue = queue
    }

    var progress: Double {
        let n = self.queue.count
        guard n > 0 else { return 0 }
        let stepDone = self.step.rawValue > 1 ? n : self.recIdx
        return Double(stepDone + self.idDone + self.spDone) / Double(3 * n)
    }

    // MARK: - Step 1 — Recognize

    var recognizeItem: StudyQueueItem? {
        guard self.recIdx < self.queue.count else { return nil }
        return self.queue[self.recIdx]
    }

    func recognizeAnswer(rating: SRSRating) async {
        guard !self.recLocked, let item = self.recognizeItem else { return }
        self.recLocked = true
        self.recRating = rating
        // Hold the rating back; the SRS write fires only once this word clears
        // Step 3 Spell (see commitLearned). This keeps `今日目標` counting full
        // 3-part completions instead of bare recognize taps.
        self.pendingRatings[item.card.id] = rating
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        try? await Task.sleep(for: .milliseconds(450))
        self.recRating = nil
        self.recLocked = false
        if self.recIdx + 1 < self.queue.count {
            self.recIdx += 1
        } else {
            self.step = .identify
        }
    }

    /// Flush the deferred recognize SRS write for a word that has now cleared
    /// all 3 parts (called when it leaves the Spell queue). Fire-and-forget —
    /// UI shouldn't block on it. Pops the rating so each word writes exactly
    /// once even if it was re-queued earlier; the backend tolerates duplicates.
    private func commitLearned(_ item: StudyQueueItem) {
        guard let rating = self.pendingRatings.removeValue(forKey: item.card.id) else { return }
        let payload = StudyAnswerPayload(
            cardId: item.card.id,
            rating: rating,
            activity: "new_recognize"
        )
        Task.detached {
            await APIClient.shared.fireAndForget(.studyAnswer, body: payload)
        }
    }

    // MARK: - Step 2 — Identify

    var identifyItem: StudyQueueItem? {
        self.idQueue.first
    }

    var identifyRemaining: Int {
        self.idQueue.count
    }

    func identifyPick(_ choice: String) {
        guard !self.idLocked, let curr = self.identifyItem else { return }
        self.idPicked = choice
        self.idLocked = true
        let ok = choice == curr.word.word
        Task {
            try? await Task.sleep(for: .milliseconds(800))
            if ok {
                self.idLocked = false
                self.idPicked = nil
                self.idDone += 1
                if !self.idQueue.isEmpty {
                    self.idQueue.removeFirst()
                }
                if self.idQueue.isEmpty { self.step = .spell }
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            } else {
                // Wrong: stay frozen on this item (keep idLocked / idPicked so
                // the wrong + answer highlight stays) and surface the peek
                // sheet. Advancing — requeue to the tail — is deferred to
                // identifyAdvance(), fired when the user taps 下一題 / dismisses
                // the sheet. Step 2/3: no /api/study/answer write — practice only.
                UINotificationFeedbackGenerator().notificationOccurred(.warning)
                self.peek = curr.word
            }
        }
    }

    /// Advance after a wrong Identify answer: requeue the missed word to the
    /// tail and unlock for the next item. Fired when the peek sheet is
    /// dismissed (下一題 button or swipe-down).
    func identifyAdvance() {
        self.peek = nil
        self.idPicked = nil
        self.idLocked = false
        guard !self.idQueue.isEmpty else { return }
        let head = self.idQueue.removeFirst()
        self.idQueue.append(head)
    }

    // MARK: - Step 3 — Spell

    var spellItem: StudyQueueItem? {
        self.spQueue.first
    }

    var spellRemaining: Int {
        self.spQueue.count
    }

    /// The string Part 3 quizzes: the hiragana reading for JA words (so the
    /// learner judges the kana), else the term form.
    func spellSubject(for item: StudyQueueItem) -> String {
        if let r = item.word.reading, !r.isEmpty { return r }
        return item.word.word
    }

    /// True when we're quizzing a kana reading distinct from the written term
    /// (JA). Drives the on-device wrong-variant generation and the view's
    /// kanji-reveal + prompt wording. `reading` is a JA-only backend field, so
    /// its presence reliably distinguishes JA-with-kana from EN.
    func spellUsesReading(for item: StudyQueueItem) -> Bool {
        guard let r = item.word.reading, !r.isEmpty else { return false }
        return r != item.word.word
    }

    /// Deterministic per-attempt: even attempts show the correct spelling,
    /// odd attempts show a wrong spelling pulled from spellingChoices. In
    /// reading mode the backend's term-based spellingChoices don't apply, so
    /// the wrong variant is scrambled from the reading on-device.
    func spellShown(for item: StudyQueueItem) -> String {
        let subject = self.spellSubject(for: item)
        let parity = self.spAttempt % 2
        if parity == 0 {
            return subject
        }
        if self.spellUsesReading(for: item) {
            return Self.fallbackMisspelling(subject)
        }
        // Pick first non-correct spelling option; fall back to a tweaked
        // version if nothing's attached.
        if let alt = item.spellingChoices?.first(where: { $0 != subject }) {
            return alt
        }
        return Self.fallbackMisspelling(subject)
    }

    private static func fallbackMisspelling(_ word: String) -> String {
        // Simple cosmetic fallback: swap last two letters when both are
        // letters. Good enough when backend forgot to attach options.
        var chars = Array(word)
        guard chars.count >= 2 else { return word + "?" }
        chars.swapAt(chars.count - 1, chars.count - 2)
        return String(chars)
    }

    func spellJudge(shown: String, says: JudgeAnswer) {
        guard !self.spLocked, let curr = self.spellItem else { return }
        self.spJudge = says
        self.spLocked = true
        let shownIsCorrect = shown == self.spellSubject(for: curr)
        let judgedRight = (says == .yes) == shownIsCorrect
        Task {
            try? await Task.sleep(for: .milliseconds(800))
            if judgedRight {
                self.spLocked = false
                self.spJudge = nil
                self.spAttempt += 1
                self.spDone += 1
                // This word just cleared all 3 parts — flush its held-back
                // recognize SRS write now (and only now).
                self.commitLearned(curr)
                if !self.spQueue.isEmpty {
                    self.spQueue.removeFirst()
                }
                if self.spQueue.isEmpty { self.step = .done }
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            } else {
                // Wrong: stay frozen (keep spLocked / spJudge so the 正解 line
                // and colour stay) and surface the peek. Requeue + spAttempt
                // bump are deferred to spellAdvance().
                UINotificationFeedbackGenerator().notificationOccurred(.warning)
                self.peek = curr.word
            }
        }
    }

    /// Advance after a wrong Spell judgment: requeue to the tail, bump the
    /// attempt parity (so the word reappears with the opposite spelling shown),
    /// and unlock. Fired when the peek sheet is dismissed.
    func spellAdvance() {
        self.peek = nil
        self.spJudge = nil
        self.spLocked = false
        self.spAttempt += 1
        guard !self.spQueue.isEmpty else { return }
        let head = self.spQueue.removeFirst()
        self.spQueue.append(head)
    }

    /// Dispatch the right advance for whichever step the wrong answer came
    /// from. Wired to the peek sheet's onDismiss so the 下一題 button and a
    /// swipe-down behave identically and never double-advance.
    func advanceFromPeek() {
        switch self.step {
        case .identify: self.identifyAdvance()
        case .spell: self.spellAdvance()
        default: self.peek = nil
        }
    }

    var spellShownIsCorrect: Bool {
        guard let curr = self.spellItem else { return false }
        return self.spellShown(for: curr) == self.spellSubject(for: curr)
    }
}
