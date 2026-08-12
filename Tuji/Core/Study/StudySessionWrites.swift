// What a study session does with its SRS answers, for both flows.
//
// 複習 and 學新字 disagree about almost everything — how a queue requeues, what
// the progress denominator is, when a rating is posted — but they agree
// completely about what happens *after* `submitAnswer` returns: track the task
// so the completion screen can drain it, fold the mastery delta into the
// session summary, keep the milestone the server attached, and count the ones
// that had to be parked.
//
// They agreed about it in two bodies. `hasPendingWrites` was byte-identical;
// `drainPendingWrites` was the same one-line delegation twice, each carrying
// the same comment about the module qualification needed to stop it recursing
// into itself; and the parked count had two names (`parkedCount` /
// `unsyncedCount`) while rendering through one view.
//
// The duplication hid an asymmetry. Only 複習 read the `.synced` body:
// `NewFlowCoordinator.commitLearned` matched `.parked` and discarded the
// response. The server emits a streak milestone **only** on the answer that
// crosses the threshold, so a milestone crossed by a `new_recognize` write was
// dropped and unrecoverable — and 學新字 had no milestone screen to show it on.
// One module means the two flows cannot answer this differently again.

import Foundation
import Observation

@MainActor
@Observable
final class StudySessionWrites {
    /// Per-word mastery before/after for the words written this session, keyed
    /// by word id. Drives the completion screens' 熟練度變化 list.
    private(set) var masteryByWord: [String: MasteryDelta] = [:]

    /// Highest streak milestone the server flagged during this session. The
    /// completion screens promote to MilestoneView when non-nil.
    private(set) var milestone: Milestone?

    /// Writes whose retries all failed. The writer parked them in the durable
    /// outbox for replay; the completion screens surface the count so a session
    /// written offline doesn't silently look fully saved.
    private(set) var parkedCount = 0

    /// Writes fired but not yet landed — drives SessionRefresh's conditional
    /// second drain (the last word's write is the one most likely to miss the
    /// short window).
    private(set) var pendingRemaining = 0

    var hasPendingWrites: Bool {
        self.pendingRemaining > 0
    }

    /// In-flight writes. Unstructured on purpose: the UI advances optimistically
    /// and the finish boundary drains them.
    private var pending: [Task<Void, Never>] = []

    private let writer: DurableAnswerWriting

    init(writer: DurableAnswerWriting = DurableAnswerWriter()) {
        self.writer = writer
    }

    /// Hand one answer to the durable writer and fold everything it returns back
    /// into the session. Returns immediately — the write is tracked, not awaited.
    ///
    /// `wordId` is passed rather than derived because the payload carries a
    /// *card* id and mastery is keyed by *word*: an atlas item can own more than
    /// one card, so the two id spaces are not interchangeable.
    func submit(_ payload: StudyAnswerPayload, wordId: String) {
        self.pendingRemaining += 1
        self.pending.append(Task {
            switch await self.writer.submitAnswer(payload) {
            case let .synced(response):
                if let delta = response.mastery {
                    self.mergeMastery(delta, wordId: wordId)
                }
                if let milestone = response.milestone {
                    // The server only emits it on the answer that crosses the
                    // threshold, so always take the one that arrived.
                    self.milestone = milestone
                }
            case .parked:
                self.parkedCount += 1
            }
            self.pendingRemaining -= 1
        })
    }

    /// Await the outstanding writes, or `timeout`, whichever lands first.
    ///
    /// Module-qualified: unqualified would resolve to this method (member lookup
    /// wins over the global) and recurse forever. That trap used to be
    /// rediscovered and commented separately in each coordinator; there is one
    /// call now, so it is explained once.
    func drainPendingWrites(within timeout: Duration) async {
        await Tuji.drainPendingWrites(self.pending, within: timeout)
    }

    /// Keep the first `before` but the latest `after` when a word is written
    /// twice in one session (複習's wrong-answer re-test) so the row shows the
    /// full session swing rather than the last hop.
    private func mergeMastery(_ delta: MasteryDelta, wordId: String) {
        guard let existing = self.masteryByWord[wordId] else {
            self.masteryByWord[wordId] = delta
            return
        }
        self.masteryByWord[wordId] = MasteryDelta(
            before: existing.before,
            after: delta.after,
            delta: delta.after - existing.before
        )
    }
}
