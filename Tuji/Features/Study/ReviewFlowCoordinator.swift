// State machine for SRS review (§III.Q). Per item:
//   .answer — user picks one of 4 MCQ choices, then one of three paths:
//     • fast correct  → the suggested rating is applied automatically and a
//       flash capsule confirms it — no reveal sheet, no extra tap. Manual
//       rating only remains where the user's judgment adds signal.
//     • slow correct  → reveal sheet with rating buttons (困難/穩定/熟練).
//     • wrong         → reveal sheet with 重來/困難 (困難 = "按錯了，其實記得";
//       anything higher would let a missed word skip its relearn).
//   Retests (a word requeued after a wrong first answer) NEVER write SRS —
//   the first attempt's 重來 already rescheduled the word, and rating a
//   just-revealed answer again would stretch the relearn interval. Correct
//   retests flash-advance; wrong ones show the sheet as study material with
//   a single 下一題.
//
// Rating writes are optimistic: the UI advances immediately while persist()
// retries in the background; answers that exhaust all retries are parked in
// the durable StudyAnswerOutbox (replayed on next launch/foreground) and
// bump `unsyncedCount` for CompleteView's notice.

import OSLog
import Observation
import SwiftUI

enum ReviewPhase: Hashable {
    case answer
    case review
}

/// What the reveal sheet is for (nil ⇒ no sheet, flash-advance path).
enum ReviewRevealMode: Hashable {
    /// Manual SRS rating buttons.
    case rate
    /// Retest wrong: study material + a single 下一題 (no write).
    case continueOnly
}

/// Feedback capsule shown while auto-advancing without the sheet.
enum ReviewFlash: Hashable {
    case autoRated(SRSRating)
    case retestPassed
}

@MainActor
@Observable
final class ReviewFlowCoordinator {
    /// Mutable so a wrong first answer can requeue the word once (appended to
    /// the tail for an in-session re-test, mirroring NewFlow).
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
    private(set) var revealMode: ReviewRevealMode?
    private(set) var flash: ReviewFlash?
    /// Items the user actually answered (one per cleared item). Drives the
    /// "今天複習" tile row on CompleteView.
    var answered: [StudyQueueItem] = []
    /// Per-word mastery before/after for the words rated this session, keyed by
    /// word id. Drives CompleteView's 熟練度變化 list.
    var masteryByWord: [String: MasteryDelta] = [:]
    /// Highest streak milestone the server flagged during this session.
    /// CompleteView promotes to MilestoneView when non-nil.
    var milestone: Milestone?
    /// Words already requeued once — enforces "one extra re-test per word".
    /// Also CompleteView's 答錯過 marker.
    var retriedIds: Set<String> = []
    /// Distinct words fully done (won't reappear). Drives the progress bar.
    var passedCount: Int = 0
    /// Consecutive correct answers (resets on a miss). At 3+ the question
    /// bubble swaps the mascot to its cheer pose.
    private(set) var combo = 0
    /// Times each word has been presented *and left* — folds into the MCQ
    /// option seed so a re-test reshuffles instead of letting "the answer was
    /// C" stand in for the word.
    private var presentedCounts: [String: Int] = [:]
    /// In-flight SRS writes (POST /api/study/answer). The UI advances
    /// optimistically without awaiting these; the finish boundary drains them.
    private var pendingWrites: [Task<Void, Never>] = []
    /// Ratings whose write exhausted all retries (e.g. offline). They're parked
    /// in StudyAnswerOutbox for replay; CompleteView surfaces the count so the
    /// session doesn't silently look fully synced.
    var unsyncedCount: Int = 0

    private let log = Logger(subsystem: "app.tuji.ios", category: "review-flow")
    private let repository: StudyRepository
    private let outbox: StudyAnswerOutbox

    init(
        queue: [StudyQueueItem],
        repository: StudyRepository = LiveStudyRepository.shared,
        outbox: StudyAnswerOutbox = .shared
    ) {
        self.queue = queue
        self.originalCount = queue.count
        self.repository = repository
        self.outbox = outbox
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

    /// MCQ option variant: bumps each time the word leaves the screen, so its
    /// re-test presents a fresh shuffle.
    func choicesVariant(for item: StudyQueueItem) -> Int {
        self.presentedCounts[item.word.id] ?? 0
    }

    /// True while the current presentation is a re-test of a word missed
    /// earlier this session.
    var isRetest: Bool {
        guard let curr = current else { return false }
        return self.retriedIds.contains(curr.word.id)
    }

    /// Computed once per answer. Fast correct answers auto-apply this; the
    /// sheet highlights it as 建議 otherwise. Mastery caps the top end: a
    /// 2-second hit on a barely-known word is normal recall, not 熟練 — only
    /// well-established words (score ≥ 50) earn the long-interval jump.
    func computeSuggestion(correct: Bool, elapsed: TimeInterval, mastery: Int?) -> SRSRating {
        if !correct { return .again }
        switch elapsed {
        case ..<3: return (mastery ?? 0) >= 50 ? .easy : .good
        case ..<7: return .good
        default: return .hard
        }
    }

    func pick(_ choice: String) {
        guard self.phase == .answer, let curr = current else { return }
        let ok = choice == curr.word.word
        let elapsed = Date.now.timeIntervalSince(self.startedAt)
        self.suggested = self.computeSuggestion(correct: ok, elapsed: elapsed, mastery: curr.mastery)
        self.picked = choice
        self.wasCorrect = ok
        self.combo = ok ? self.combo + 1 : 0
        UIImpactFeedbackGenerator(
            style: ok ? .light : .medium
        ).impactOccurred()
        self.phase = .review
        self.recordAnswered(curr)

        if self.retriedIds.contains(curr.word.id) {
            // Re-test: practice only, never a second SRS write (the first
            // attempt's 重來 already rescheduled this word).
            self.passedCount += 1
            if ok {
                self.flash = .retestPassed
                self.scheduleAdvance(after: .milliseconds(700))
            } else {
                self.revealMode = .continueOnly
            }
        } else if ok, self.suggested != .hard {
            // Fast correct: the suggestion is unambiguous — apply it and keep
            // the session moving instead of raising a sheet to confirm it.
            self.passedCount += 1
            self.applyRating(self.suggested, for: curr)
            self.flash = .autoRated(self.suggested)
            self.scheduleAdvance(after: .milliseconds(700))
        } else {
            // Wrong, or correct-but-slow: the user's own judgment carries
            // signal, so surface the sheet with rating buttons.
            self.revealMode = .rate
        }
    }

    /// Rating buttons in the reveal sheet. Wrong answers offer only 重來/困難
    /// (困難 = misclick escape hatch) — anything higher would let a missed
    /// word skip its relearn. Correct-but-slow answers pick among the three
    /// positive ratings.
    var availableRatings: [SRSRating] {
        if self.wasCorrect {
            return [.hard, .good, .easy]
        }
        return [.again, .hard]
    }

    /// Manual rating from the reveal sheet (revealMode == .rate only).
    func rate(_ r: SRSRating) {
        guard self.phase == .review, self.revealMode == .rate,
              self.rated == nil, let curr = current
        else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        // Wrong first attempt → requeue the word once for an in-session
        // re-test (appended to the tail). The re-test itself never requeues
        // again, and a correct first answer passes straight through.
        if !self.wasCorrect {
            self.retriedIds.insert(curr.word.id)
            self.queue.append(curr)
        } else {
            self.passedCount += 1
        }
        self.applyRating(r, for: curr)
        // Fixed, network-independent beat so the button fill registers.
        self.scheduleAdvance(after: .milliseconds(300))
    }

    /// 下一題 on the retest-wrong sheet (revealMode == .continueOnly).
    func continueFromReveal() {
        guard self.phase == .review, self.revealMode == .continueOnly else { return }
        self.scheduleAdvance(after: .zero)
    }

    // MARK: - Internals

    /// One row per word on CompleteView, even when re-tested twice.
    private func recordAnswered(_ item: StudyQueueItem) {
        if !self.answered.contains(where: { $0.word.id == item.word.id }) {
            self.answered.append(item)
        }
    }

    /// Record + persist one SRS rating (optimistically, in the background).
    private func applyRating(_ r: SRSRating, for item: StudyQueueItem) {
        self.rated = r
        let payload = StudyAnswerPayload(
            cardId: item.card.id,
            rating: r,
            responseMs: Int(Date.now.timeIntervalSince(self.startedAt) * 1000),
            activity: "mcq"
        )
        let wordId = item.word.id
        self.pendingWrites.append(Task { await self.persist(payload, wordId: wordId) })
    }

    private func scheduleAdvance(after delay: Duration) {
        Task {
            if delay > .zero {
                try? await Task.sleep(for: delay)
            }
            self.advance()
        }
    }

    /// Writes one SRS answer with a few retries and folds the returned
    /// mastery/milestone back into session state. Runs detached from the UI.
    private func persist(_ payload: StudyAnswerPayload, wordId: String) async {
        for attempt in 0..<3 {
            if Task.isCancelled { return }
            do {
                let resp = try await self.repository.submitAnswer(payload)
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
        // All retries exhausted — park it in the durable outbox (replayed on
        // next launch/foreground) and flag the session summary.
        self.outbox.add(payload)
        self.unsyncedCount += 1
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
        if let leaving = current {
            self.presentedCounts[leaving.word.id, default: 0] += 1
        }
        if self.index + 1 >= self.queue.count {
            // Last item: give outstanding SRS writes a brief window to land so
            // CompleteView's mastery deltas are populated, but cap it so a slow
            // or dead network can't hang the summary. Module-qualified — the
            // unqualified name resolves to the instance method below.
            Task {
                await Tuji.drainPendingWrites(self.pendingWrites, within: .milliseconds(800))
                self.finished = true
            }
        } else {
            self.index += 1
            self.phase = .answer
            self.picked = nil
            self.rated = nil
            self.revealMode = nil
            self.flash = nil
            self.startedAt = .now
        }
    }

    /// Await outstanding writes (bounded). Mirrors NewFlowCoordinator; also
    /// lets tests assert on persisted payloads without real sleeps.
    func drainPendingWrites(within timeout: Duration) async {
        await Tuji.drainPendingWrites(self.pendingWrites, within: timeout)
    }
}
