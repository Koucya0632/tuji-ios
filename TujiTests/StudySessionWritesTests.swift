// Pins what a study session does with an answer after the writer returns:
// fold the mastery delta, keep the milestone, count a park, and let the
// completion screen drain. Both flows share this module, so these assertions
// hold for 複習 and 學新字 at once — the merge rule in particular used to be
// reachable only by driving a full 複習 session to its second rating.

import Foundation
import Testing
@testable import Tuji

@MainActor
struct StudySessionWritesTests {
    private func payload(card: String = "c1") -> StudyAnswerPayload {
        StudyAnswerPayload(cardId: card, rating: .good, activity: "mcq")
    }

    @Test
    func syncedResponseFoldsMasteryAndMilestone() async {
        let writer = StubWriter()
        writer.outcome = .synced(
            StudyAnswerResponse(
                ok: true,
                milestone: Milestone(streak: 100),
                mastery: MasteryDelta(before: 10, after: 20, delta: 10)
            )
        )
        let writes = StudySessionWrites(writer: writer)

        writes.submit(self.payload(), wordId: "w1")
        await writes.drainPendingWrites(within: .seconds(2))

        #expect(writes.masteryByWord["w1"]?.after == 20)
        #expect(writes.milestone?.streak == 100)
        #expect(writes.parkedCount == 0)
        #expect(!writes.hasPendingWrites)
    }

    @Test
    func parkedResponseCountsAndFoldsNothing() async {
        let writer = StubWriter()
        writer.outcome = .parked
        let writes = StudySessionWrites(writer: writer)

        writes.submit(self.payload(), wordId: "w1")
        await writes.drainPendingWrites(within: .seconds(2))

        #expect(writes.parkedCount == 1)
        #expect(writes.masteryByWord.isEmpty)
        #expect(writes.milestone == nil)
    }

    /// A word written twice in one session (複習's wrong-answer re-test) shows
    /// the full swing: the first `before` against the latest `after`.
    @Test
    func twoWritesForOneWordKeepTheFirstBefore() async {
        let writer = StubWriter()
        writer.outcome = .synced(
            StudyAnswerResponse(
                ok: true,
                milestone: nil,
                mastery: MasteryDelta(before: 10, after: 14, delta: 4)
            )
        )
        let writes = StudySessionWrites(writer: writer)
        writes.submit(self.payload(), wordId: "w1")
        await writes.drainPendingWrites(within: .seconds(2))

        writer.outcome = .synced(
            StudyAnswerResponse(
                ok: true,
                milestone: nil,
                mastery: MasteryDelta(before: 14, after: 31, delta: 17)
            )
        )
        writes.submit(self.payload(), wordId: "w1")
        await writes.drainPendingWrites(within: .seconds(2))

        let merged = writes.masteryByWord["w1"]
        #expect(merged?.before == 10)
        #expect(merged?.after == 31)
        #expect(merged?.delta == 21)
    }

    /// Mastery is keyed by *word* while the payload carries a *card* id: an
    /// atlas item can own more than one card, so the two id spaces are not
    /// interchangeable and the caller states the word.
    @Test
    func masteryIsKeyedByWordNotCard() async {
        let writer = StubWriter()
        let writes = StudySessionWrites(writer: writer)

        writes.submit(self.payload(card: "atlas:card-a"), wordId: "atlas:item-1")
        await writes.drainPendingWrites(within: .seconds(2))

        #expect(writes.masteryByWord["atlas:item-1"] != nil)
        #expect(writes.masteryByWord["atlas:card-a"] == nil)
    }

    /// The drain is bounded: a write that has not landed does not hold the
    /// completion screen. Asserted as a *decision* — the drain returned while
    /// the write was still outstanding — not as a wall-clock bound. Timing
    /// assertions do not survive CI, which runs every @MainActor suite in
    /// parallel and starves anything waiting on a beat.
    @Test
    func drainReturnsWhileASlowWriteIsStillOutstanding() async {
        let writer = StubWriter()
        writer.hold = true
        let writes = StudySessionWrites(writer: writer)
        writes.submit(self.payload(), wordId: "w1")

        await writes.drainPendingWrites(within: .milliseconds(50))

        #expect(writes.hasPendingWrites)
        #expect(writes.masteryByWord.isEmpty)

        // Let it finish so the suite leaves nothing running.
        writer.release()
        await writes.drainPendingWrites(within: .seconds(10))
        #expect(!writes.hasPendingWrites)
    }
}

@MainActor
private final class StubWriter: DurableAnswerWriting {
    private(set) var answers: [StudyAnswerPayload] = []
    var outcome: StudyWriteOutcome = .synced(
        StudyAnswerResponse(
            ok: true,
            milestone: nil,
            mastery: MasteryDelta(before: 0, after: 5, delta: 5)
        )
    )
    /// Parks the write on a continuation instead of a sleep, so the drain's
    /// bound can be exercised without a timer the CI scheduler can starve.
    var hold = false
    private var continuation: CheckedContinuation<Void, Never>?

    func submitAnswer(_ payload: StudyAnswerPayload) async -> StudyWriteOutcome {
        self.answers.append(payload)
        if self.hold {
            await withCheckedContinuation { self.continuation = $0 }
        }
        return self.outcome
    }

    func release() {
        self.continuation?.resume()
        self.continuation = nil
    }
}
