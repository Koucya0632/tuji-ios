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

    @Test
    func drainReturnsAtTheTimeoutWithoutWaitingOutASlowWrite() async {
        let writer = StubWriter()
        writer.delay = .seconds(30)
        let writes = StudySessionWrites(writer: writer)
        writes.submit(self.payload(), wordId: "w1")

        let started = ContinuousClock.now
        await writes.drainPendingWrites(within: .milliseconds(200))

        // Generous ceiling: CI runs every @MainActor suite in parallel, so the
        // assertion is 「it did not wait out the 30s write」, not a tight bound.
        #expect(ContinuousClock.now - started < .seconds(10))
        #expect(writes.hasPendingWrites)
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
    /// Held before answering, so the drain's timeout can be exercised.
    var delay: Duration?

    func submitAnswer(_ payload: StudyAnswerPayload) async -> StudyWriteOutcome {
        self.answers.append(payload)
        if let delay { try? await Task.sleep(for: delay) }
        return self.outcome
    }
}
