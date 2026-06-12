// State machine for the "learn new words" three-step micro lesson
// (§III.P). Step 1 Recognize is the *only* step that writes SRS via
// POST /api/study/answer; Step 2 Identify (MCQ) and Step 3 Spell are
// pure practice — wrong answers re-queue, no backend write.

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
        // Fire and forget the SRS write — UI should not block on it. The
        // backend tolerates duplicate writes if the user retries.
        let payload = StudyAnswerPayload(
            cardId: item.card.id,
            rating: rating,
            activity: "new_recognize"
        )
        Task.detached {
            await APIClient.shared.fireAndForget(.studyAnswer, body: payload)
        }
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
            self.idLocked = false
            self.idPicked = nil
            if ok {
                self.idDone += 1
                if !self.idQueue.isEmpty {
                    self.idQueue.removeFirst()
                }
                if self.idQueue.isEmpty { self.step = .spell }
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            } else {
                let head = self.idQueue.removeFirst()
                self.idQueue.append(head)
                UINotificationFeedbackGenerator().notificationOccurred(.warning)
                self.peek = curr.word
                // Step 2/3: no /api/study/answer write — practice only.
            }
        }
    }

    // MARK: - Step 3 — Spell

    var spellItem: StudyQueueItem? {
        self.spQueue.first
    }

    var spellRemaining: Int {
        self.spQueue.count
    }

    /// Deterministic per-attempt: even attempts show the correct spelling,
    /// odd attempts show a wrong spelling pulled from spellingChoices.
    func spellShown(for item: StudyQueueItem) -> String {
        let parity = self.spAttempt % 2
        if parity == 0 {
            return item.word.word
        }
        // Pick first non-correct spelling option; fall back to a tweaked
        // version if nothing's attached.
        if let alt = item.spellingChoices?.first(where: { $0 != item.word.word }) {
            return alt
        }
        return Self.fallbackMisspelling(item.word.word)
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
        let shownIsCorrect = shown == curr.word.word
        let judgedRight = (says == .yes) == shownIsCorrect
        Task {
            try? await Task.sleep(for: .milliseconds(800))
            self.spLocked = false
            self.spJudge = nil
            self.spAttempt += 1
            if judgedRight {
                self.spDone += 1
                if !self.spQueue.isEmpty {
                    self.spQueue.removeFirst()
                }
                if self.spQueue.isEmpty { self.step = .done }
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            } else {
                let head = self.spQueue.removeFirst()
                self.spQueue.append(head)
                UINotificationFeedbackGenerator().notificationOccurred(.warning)
                self.peek = curr.word
            }
        }
    }

    var spellShownIsCorrect: Bool {
        guard let curr = self.spellItem else { return false }
        return self.spellShown(for: curr) == curr.word.word
    }
}
