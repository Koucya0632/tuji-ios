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
    // Mutable so a wrong first answer can requeue the word once (appended to
    // the tail for an in-session re-test, mirroring NewFlow).
    var queue: [StudyQueueItem]
    /// Distinct word count at start — the stable progress denominator so
    /// requeued re-tests don't inflate it.
    let originalCount: Int
    var index: Int = 0
    var phase: ReviewPhase = .answer
    var picked: String?
    var wasCorrect: Bool = false
    var suggested: SRSRating = .good
    var rated: SRSRating?
    var startedAt: Date = .now
    var finished: Bool = false
    /// Items the user actually rated (one per cleared item). Drives the
    /// "今天複習" tile row on CompleteView.
    var answered: [StudyQueueItem] = []
    /// Per-word mastery before/after for the words rated this session, keyed by
    /// word id. Drives CompleteView's 熟練度變化 list.
    var masteryByWord: [String: MasteryDelta] = [:]
    /// Highest streak milestone the server flagged during this session.
    /// CompleteView promotes to MilestoneView when non-nil.
    var milestone: Milestone?
    /// Words already requeued once — enforces "one extra re-test per word".
    var retriedIds: Set<String> = []
    /// Distinct words fully done (won't reappear). Drives the progress bar.
    var passedCount: Int = 0
    /// In-flight SRS writes (POST /api/study/answer). The UI advances
    /// optimistically without awaiting these; the finish boundary drains them.
    private var pendingWrites: [Task<Void, Never>] = []

    private let log = Logger(subsystem: "app.tuji.ios", category: "review-flow")

    init(queue: [StudyQueueItem]) {
        self.queue = queue
        self.originalCount = queue.count
    }

    var current: StudyQueueItem? {
        guard self.index < self.queue.count else { return nil }
        return self.queue[self.index]
    }

    var progress: Double {
        guard self.originalCount > 0 else { return 0 }
        // Based on distinct words completed (passedCount) so requeued re-tests
        // never push the bar backward. A half-step while revealing keeps it
        // feeling responsive.
        let boost = self.phase == .review ? 0.5 : 0
        return min(1, (Double(self.passedCount) + boost) / Double(self.originalCount))
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

    /// Optimistic: record the rating, run all the local bookkeeping, and
    /// advance on a fixed beat. The SRS write (POST /api/study/answer) is fired
    /// into `pendingWrites` and never blocks the UI — perceived latency becomes
    /// a constant ~300ms instead of network-RTT + 450ms.
    func rate(_ r: SRSRating) {
        guard self.phase == .review, let curr = current else { return }
        self.rated = r
        UIImpactFeedbackGenerator(style: .light).impactOccurred()

        // Local bookkeeping — none of this needs the server, so do it now.
        // One row per word on CompleteView, even when re-tested twice.
        if !self.answered.contains(where: { $0.word.id == curr.word.id }) {
            self.answered.append(curr)
        }
        // Wrong first attempt → requeue the word once for an in-session
        // re-test (appended to the tail). The re-test itself never requeues
        // again, and a correct first answer passes straight through.
        let isRetest = self.retriedIds.contains(curr.word.id)
        if !self.wasCorrect, !isRetest {
            self.retriedIds.insert(curr.word.id)
            self.queue.append(curr)
        } else {
            self.passedCount += 1
        }

        // Persist in the background; mastery/milestone merge in when it lands.
        let payload = StudyAnswerPayload(
            cardId: curr.card.id,
            rating: r,
            responseMs: Int(Date.now.timeIntervalSince(self.startedAt) * 1000),
            activity: "mcq"
        )
        let wordId = curr.word.id
        self.pendingWrites.append(Task { await self.persist(payload, wordId: wordId) })

        // Fixed, network-independent beat so the button fill + check/✕ register,
        // then move on.
        Task {
            try? await Task.sleep(for: .milliseconds(300))
            self.advance()
        }
    }

    /// Writes one SRS answer with a few retries and folds the returned
    /// mastery/milestone back into session state. Runs detached from the UI.
    private func persist(_ payload: StudyAnswerPayload, wordId: String) async {
        for attempt in 0 ..< 3 {
            if Task.isCancelled { return }
            do {
                let resp: StudyAnswerResponse = try await APIClient.shared.post(
                    .studyAnswer,
                    body: payload
                )
                if let m = resp.mastery { self.mergeMastery(m, wordId: wordId) }
                if let ms = resp.milestone {
                    // Server only emits the milestone on the answer that crosses
                    // the threshold, so always overwrite when present.
                    self.milestone = ms
                }
                return
            } catch {
                self.log.error(
                    "rate persist failed (attempt \(attempt + 1)): \(error.localizedDescription, privacy: .public)"
                )
                if attempt < 2 {
                    try? await Task.sleep(for: .milliseconds(400 * (attempt + 1)))
                }
            }
        }
    }

    /// Keep the first `before` but the latest `after` when a word is rated
    /// twice in one session (wrong-answer re-test) so the row shows the full
    /// session swing.
    private func mergeMastery(_ m: MasteryDelta, wordId: String) {
        if let existing = self.masteryByWord[wordId] {
            self.masteryByWord[wordId] = MasteryDelta(
                before: existing.before,
                after: m.after,
                delta: m.after - existing.before
            )
        } else {
            self.masteryByWord[wordId] = m
        }
    }

    private func advance() {
        if self.index + 1 >= self.queue.count {
            // Last item: give outstanding SRS writes a brief window to land so
            // CompleteView's mastery deltas are populated, but cap it so a slow
            // or dead network can't hang the summary.
            Task {
                await self.drainPendingWrites(within: .milliseconds(800))
                self.finished = true
            }
        } else {
            self.index += 1
            self.phase = .answer
            self.picked = nil
            self.rated = nil
            self.startedAt = .now
        }
    }

    /// Await every in-flight write, or `timeout`, whichever comes first. Writes
    /// that miss the window keep running and still merge via @Observable.
    private func drainPendingWrites(within timeout: Duration) async {
        let writes = self.pendingWrites
        guard !writes.isEmpty else { return }
        await withTaskGroup(of: Void.self) { group in
            group.addTask { for w in writes { await w.value } }
            group.addTask { try? await Task.sleep(for: timeout) }
            await group.next()
            group.cancelAll()
        }
    }
}
