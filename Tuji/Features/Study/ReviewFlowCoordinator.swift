// State machine for SRS review (§III.Q). Two phases per item:
//   .answer  — user picks one of 4 MCQ choices
//   .review  — reveal correct + 3/4 SRS rating buttons (suggested
//              based on response time + correctness)
//
// Every .rate call writes /api/study/answer (this is the only place SRS
// gets persisted during review). A failed POST keeps us in .review so
// the user can retry.

import OSLog
import Observation
import SwiftUI

enum ReviewPhase: Hashable {
    case answer
    case review
}

@MainActor
@Observable
final class ReviewFlowCoordinator {
    let queue: [StudyQueueItem]
    var index: Int = 0
    var phase: ReviewPhase = .answer
    var picked: String?
    var wasCorrect: Bool = false
    var suggested: SRSRating = .good
    var rated: SRSRating?
    var startedAt: Date = .now
    var rateError: Error?
    var finished: Bool = false

    private let log = Logger(subsystem: "app.tuji.ios", category: "review-flow")

    init(queue: [StudyQueueItem]) {
        self.queue = queue
    }

    var current: StudyQueueItem? {
        guard self.index < self.queue.count else { return nil }
        return self.queue[self.index]
    }

    var progress: Double {
        guard !self.queue.isEmpty else { return 0 }
        // Each item contributes 1/N when answered + 1/N when rated. We
        // weight phase contribution to 0.5 so the bar moves visibly
        // after pick and again after rate.
        let perItem = 1.0 / Double(self.queue.count)
        let phaseBoost = self.phase == .review ? perItem * 0.5 : 0
        return Double(self.index) * perItem + phaseBoost
    }

    /// Computed once per item enter. Used to highlight the "建議" rating.
    func computeSuggestion(correct: Bool, elapsed: TimeInterval) -> SRSRating {
        if !correct { return .again }
        switch elapsed {
        case ..<3: return .easy
        case ..<7: return .good
        default: return .hard
        }
    }

    func pick(_ choice: String) {
        guard self.phase == .answer, let curr = current else { return }
        let ok = choice == curr.word.word
        let elapsed = Date.now.timeIntervalSince(self.startedAt)
        self.suggested = self.computeSuggestion(correct: ok, elapsed: elapsed)
        self.picked = choice
        self.wasCorrect = ok
        UIImpactFeedbackGenerator(
            style: ok ? .light : .medium
        ).impactOccurred()
        self.phase = .review
    }

    /// Rating buttons available in the review footer. Wrong answers get
    /// all four (so .again exists), correct answers skip .again.
    var availableRatings: [SRSRating] {
        if self.wasCorrect {
            return [.hard, .good, .easy]
        }
        return [.again, .hard, .good, .easy]
    }

    func rate(_ r: SRSRating) async {
        guard self.phase == .review, let curr = current else { return }
        self.rated = r
        self.rateError = nil
        let elapsedMs = Int(Date.now.timeIntervalSince(self.startedAt) * 1000)
        let payload = StudyAnswerPayload(
            cardId: curr.card.id,
            rating: r,
            responseMs: elapsedMs,
            activity: "mcq"
        )
        do {
            let _: StudyAnswerResponse = try await APIClient.shared.post(
                .studyAnswer,
                body: payload
            )
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            try? await Task.sleep(for: .milliseconds(450))
            self.advance()
        } catch {
            self.rateError = error
            self.rated = nil
            self.log.error("rate failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func advance() {
        if self.index + 1 >= self.queue.count {
            self.finished = true
        } else {
            self.index += 1
            self.phase = .answer
            self.picked = nil
            self.rated = nil
            self.startedAt = .now
        }
    }
}
