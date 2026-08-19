// State machine for SRS review (§III.Q). Per item:
//   .answer — the user may flip the image over for the gloss (求救提示, see
//     `toggleHint`), then picks one of 4 MCQ choices, then one of three paths:
//     • fast correct  → the suggested rating is applied automatically and a
//       flash capsule confirms it — no reveal sheet, no extra tap. Manual
//       rating only remains where the user's judgment adds signal.
//     • slow correct  → reveal sheet with rating buttons (困難/穩定/熟練).
//     • wrong         → reveal sheet with 重來/困難 (困難 = "按錯了，其實記得";
//       anything higher would let a missed word skip its relearn).
//   A hinted item takes the wrong-answer rating table either way — see
//   `toggleHint` and docs/adr/0007-review-hint-costs-a-downgrade.md.
//
//   Retests (a word requeued after a wrong first answer) NEVER write SRS —
//   the first attempt's 重來 already rescheduled the word, and rating a
//   just-revealed answer again would stretch the relearn interval. Correct
//   retests flash-advance; wrong ones show the sheet as study material with
//   a single 下一題.
//
// Rating writes are optimistic: the UI advances immediately while persist()
// hands the answer to the DurableAnswerWriter in the background. The writer
// retries and, on exhaustion, parks the answer in the durable StudyAnswerOutbox
// (replayed on next launch/foreground) and reports `.parked`, which bumps
// `unsyncedCount` for CompleteView's notice.

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
    /// The user flipped this presentation's image over for the gloss. Sticky
    /// within the presentation — flipping back does not un-see it — and reset
    /// in `advance()` along with the rest of the per-item state.
    private(set) var hinted: Bool = false
    /// Which face the card is showing right now. Distinct from `hinted`: this
    /// one goes back and forth, that one only ever turns on. It lives here
    /// rather than in the view because it has to reset per item, and the view
    /// is reused across items.
    private(set) var hintFaceUp: Bool = false
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
    /// Words already requeued once — enforces "one extra re-test per word".
    /// Also CompleteView's 答錯過 marker.
    var retriedIds: Set<String> = []
    /// Distinct words fully done (won't reappear). Drives the progress bar.
    var passedCount: Int = 0
    /// Times each word has been presented *and left* — folds into the MCQ
    /// option seed so a re-test reshuffles instead of letting "the answer was
    /// C" stand in for the word.
    private var presentedCounts: [String: Int] = [:]

    /// Everything that happens to an answer after it is handed to the writer:
    /// the drain, the mastery fold, the milestone, the parked count. Shared with
    /// 學新字 — see StudySessionWrites.
    let writes: StudySessionWrites

    private let queueProvider: StudyQueueProviding

    /// How long the flow pauses before advancing past an answered item.
    ///
    /// Injected for the same reason 學新字 injects its own: the advance beats
    /// are 300–800 ms of real `Task.sleep`, and CI runs every `@MainActor`
    /// suite in parallel on one actor — a starved run turned a 300 ms beat into
    /// a minute and failed every assertion after it. This coordinator was the
    /// one that still had no seam at all, so its tests polled a wall clock and
    /// carried a nine-line comment about the resulting flake instead of closing
    /// it.
    private let beat: @Sendable (Duration) async -> Void

    /// The advances in flight. Unstructured `Task`s that outlive the view: 複習
    /// scheduled its beats and never kept them, so leaving mid-answer still ran
    /// `advance()` — and `drainPendingWrites`, and `finished = true` — on a
    /// coordinator whose screen was gone.
    ///
    /// 學新字 carries the same array for the same reason, and the comment on
    /// `NewFlowCoordinator.recognizeAnswer` records that the defect had already
    /// been declared fixed once while one of its three stages still leaked. This
    /// was the fourth copy of that stage, in the other flow, and it had no array
    /// at all.
    private var pendingBeats: [Task<Void, Never>] = []

    init(
        queue: [StudyQueueItem],
        writer: DurableAnswerWriting = DurableAnswerWriter(),
        queueProvider: StudyQueueProviding = StudyQueueStore.shared,
        beat: @escaping @Sendable (Duration) async -> Void = { try? await Task.sleep(for: $0) }
    ) {
        self.queue = queue
        self.originalCount = queue.count
        self.writes = StudySessionWrites(writer: writer)
        self.queueProvider = queueProvider
        self.beat = beat
    }

    /// Fetch the next round's due queue for 再來一輪; empty ⇒ nothing left. The
    /// view uses this to spin up a fresh coordinator (a clean full reset), so the
    /// fetch is injected and testable instead of the view reaching
    /// `StudyQueueStore.shared`.
    func fetchAnotherRound() async -> [StudyQueueItem] {
        await (try? self.queueProvider.fetch(mode: .review)) ?? []
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

    /// Flip the image over to read the gloss, and back. Only while the item is
    /// still unanswered: the reveal sheet rests at `.fraction(0.4)` with
    /// background interaction enabled, so the hero stays tappable underneath it
    /// and an answered item would otherwise still turn.
    ///
    /// Asking for the gloss is the user reporting that they could not retrieve
    /// the word, so it is remembered for the rating (`hinted`) even if they
    /// flip straight back.
    func toggleHint() {
        guard self.phase == .answer else { return }
        self.hintFaceUp.toggle()
        if self.hintFaceUp { self.hinted = true }
    }

    /// Whether the 8-second "點一下圖片" nudge still has anything to teach on
    /// this item. The view owns the timer; this owns the decision.
    var canNudge: Bool {
        self.phase == .answer && !self.hinted && !self.isRetest
    }

    /// Computed once per answer. Fast correct answers auto-apply this; the
    /// sheet highlights it as 建議 otherwise. Mastery caps the top end: a
    /// 2-second hit on a barely-known word is normal recall, not 熟練 — only
    /// well-established words (score ≥ 50) earn the long-interval jump.
    ///
    /// A hinted item is capped at 困難 regardless of speed. That cap is also
    /// what switches off the auto-rate path in `pick()`, which requires a
    /// suggestion other than 困難 — see ADR-0007.
    func computeSuggestion(
        correct: Bool,
        elapsed: TimeInterval,
        mastery: Int?,
        hinted: Bool = false
    )
        -> SRSRating
    {
        if !correct { return .again }
        if hinted { return .hard }
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
        self.suggested = self.computeSuggestion(
            correct: ok,
            elapsed: elapsed,
            mastery: curr.mastery,
            hinted: self.hinted
        )
        self.picked = choice
        self.wasCorrect = ok
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
    ///
    /// A hinted answer takes the wrong-answer table even when it was right:
    /// the user told us they could not retrieve the word, so 穩定/熟練 are not
    /// theirs to claim. Only the *suggestion* still tracks correctness.
    var availableRatings: [SRSRating] {
        guard self.wasCorrect, !self.hinted else {
            return [.again, .hard]
        }
        return [.hard, .good, .easy]
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
            activity: "mcq",
            hinted: self.hinted
        )
        self.writes.submit(payload, wordId: item.word.id)
    }

    private func scheduleAdvance(after delay: Duration) {
        self.pendingBeats.append(Task {
            if delay > .zero {
                await self.beat(delay)
            }
            guard !Task.isCancelled else { return }
            self.advance()
        })
    }

    /// Drops every advance still waiting. 先離開 calls this before dismissing;
    /// without it the beat outlives the screen (see `pendingBeats`).
    func cancelPendingBeats() {
        for task in self.pendingBeats {
            task.cancel()
        }
        self.pendingBeats.removeAll()
    }

    private func advance() {
        if let leaving = current {
            self.presentedCounts[leaving.word.id, default: 0] += 1
        }
        if self.index + 1 >= self.queue.count {
            // Last item: give outstanding SRS writes a brief window to land so
            // CompleteView's mastery deltas are populated, but cap it so a slow
            // or dead network can't hang the summary.
            Task {
                await self.writes.drainPendingWrites(within: .milliseconds(800))
                self.finished = true
            }
        } else {
            self.index += 1
            self.phase = .answer
            self.picked = nil
            self.hinted = false
            self.hintFaceUp = false
            self.rated = nil
            self.revealMode = nil
            self.flash = nil
            self.startedAt = .now
        }
    }
}
