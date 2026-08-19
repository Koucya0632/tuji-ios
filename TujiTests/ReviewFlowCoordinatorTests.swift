// Pins the review answer paths: fast-correct auto-rating (with the
// mastery-capped suggestion), the wrong-answer restricted ratings + requeue,
// and the retest contract — reshuffled options, no second SRS write. The
// advance beats are real (300-800ms) Tasks, so the end-to-end test polls
// until each beat lands (fixed sleeps raced the beats on slow CI runners);
// everything else asserts synchronously. Writes go through an injected
// DurableAnswerWriting spy, so the coordinator's reaction to `.synced` (fold
// mastery) and `.parked` (bump unsyncedCount) is asserted directly.

import Foundation
import Testing
@testable import Tuji

@MainActor
struct ReviewFlowCoordinatorTests {
    private func makeQueue() throws -> [StudyQueueItem] {
        let json = """
        [
          {
            "card": { "id": 11, "cardType": "flashcard", "deckKey": "core" },
            "word": {
              "id": "w-fork", "word": "fork", "chinese": "叉子", "imageUrl": "",
              "pronunciation": "", "reading": null, "targetLanguage": "en", "category": "kitchen"
            },
            "choices": ["fork", "spoon", "ladle", "whisk"],
            "spellingChoices": null,
            "mastery": 10
          },
          {
            "card": { "id": 22, "cardType": "flashcard", "deckKey": "core" },
            "word": {
              "id": "w-cup", "word": "cup", "chinese": "杯子", "imageUrl": "",
              "pronunciation": "", "reading": null, "targetLanguage": "en", "category": "kitchen"
            },
            "choices": ["cup", "plate", "bowl", "jar"],
            "spellingChoices": null,
            "mastery": 80
          }
        ]
        """
        return try JSONDecoder.tuji.decode([StudyQueueItem].self, from: Data(json.utf8))
    }

    /// Yields the main actor in short beats until `condition` holds. Returns
    /// on the first poll that passes, so the happy path stays as fast as the
    /// beat — the ceiling only bounds a genuinely broken build. It must be
    /// extravagant: Swift Testing runs every @MainActor suite in parallel on
    /// one main actor, and on CI runners that starved a beat past 5s.
    private func waitUntil(
        timeout: Duration = .seconds(60),
        _ condition: () -> Bool
    ) async throws {
        let deadline = ContinuousClock.now + timeout
        while !condition(), ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(50))
        }
    }

    @Test
    func suggestionCapsEasyForLowMastery() throws {
        let queue = try self.makeQueue()
        let c = ReviewFlowCoordinator(queue: queue, writer: SpyAnswerWriter())
        // Fast + wobbly word → good, not easy; fast + established word → easy.
        #expect(c.computeSuggestion(correct: true, elapsed: 1, mastery: 10) == .good)
        #expect(c.computeSuggestion(correct: true, elapsed: 1, mastery: 80) == .easy)
        #expect(c.computeSuggestion(correct: true, elapsed: 5, mastery: 80) == .good)
        #expect(c.computeSuggestion(correct: true, elapsed: 10, mastery: 80) == .hard)
        #expect(c.computeSuggestion(correct: false, elapsed: 1, mastery: 80) == .again)
    }

    @Test
    func fastCorrectAutoRatesWithoutSheet() async throws {
        let queue = try self.makeQueue()
        let writer = SpyAnswerWriter()
        let c = ReviewFlowCoordinator(queue: queue, writer: writer, beat: { _ in })
        c.pick("fork")
        // No sheet, flash capsule instead, suggested applied (mastery 10 → 穩定).
        #expect(c.revealMode == nil)
        #expect(c.flash == .autoRated(.good))
        #expect(c.rated == .good)
        #expect(c.passedCount == 1)
        await c.writes.drainPendingWrites(within: .seconds(2))
        #expect(writer.answers.map(\.rating) == ["穩定"])
        #expect(writer.answers.first?.responseMs != nil)
        // The .synced response's mastery delta folds into the session summary.
        #expect(c.writes.masteryByWord["w-fork"]?.after == 20)
    }

    @Test
    func parkedWriteBumpsUnsyncedCountAndSkipsMastery() async throws {
        let queue = try self.makeQueue()
        let writer = SpyAnswerWriter()
        writer.outcome = .parked
        let c = ReviewFlowCoordinator(queue: queue, writer: writer)
        // Fast correct → auto-rate fires exactly one write, which the writer
        // reports as parked (offline). The coordinator must count it, not merge
        // a (non-existent) mastery delta.
        c.pick("fork")
        #expect(c.rated == .good)
        await c.writes.drainPendingWrites(within: .seconds(2))
        #expect(writer.answers.count == 1)
        #expect(c.writes.parkedCount == 1)
        #expect(c.writes.masteryByWord["w-fork"] == nil)
    }

    @Test
    func wrongAnswerRestrictsRatingsAndRequeues() throws {
        let queue = try self.makeQueue()
        let c = ReviewFlowCoordinator(queue: queue, writer: SpyAnswerWriter())
        c.pick("spoon")
        #expect(c.revealMode == .rate)
        #expect(c.suggested == .again)
        #expect(c.availableRatings == [.again, .hard])
        c.rate(.again)
        // Requeued to the tail exactly once; not counted as passed yet.
        #expect(c.queue.map(\.word.id) == ["w-fork", "w-cup", "w-fork"])
        #expect(c.retriedIds.contains("w-fork"))
        #expect(c.passedCount == 0)
    }

    @Test
    func retestReshufflesOptionsAndNeverWritesAgain() async throws {
        let queue = try self.makeQueue()
        let writer = SpyAnswerWriter()
        // Instant beats: the advance delays are the coordinator's, not the
        // test's, and a starved CI actor used to stretch a 300ms one past the
        // poll ceiling and fail every assertion after it.
        let c = ReviewFlowCoordinator(queue: queue, writer: writer, beat: { _ in })

        // Item 1 (fork): wrong → manual 重來 → requeued.
        c.pick("spoon")
        c.rate(.again)
        try await self.waitUntil { c.current?.word.id == "w-cup" } // 300ms advance beat
        #expect(c.current?.word.id == "w-cup")

        // Item 2 (cup): fast correct → auto-rated (mastery 80 → 熟練).
        //
        // "Fast" is still wall-clock — `pick()` reads `Date.now - startedAt` —
        // so it is stated rather than assumed, the mirror of
        // `slowCorrectStillAsksForManualRating` backdating it to force the
        // other branch.
        c.startedAt = .now
        c.pick("cup")
        #expect(c.flash == .autoRated(.easy))
        try await self.waitUntil { c.current?.word.id == "w-fork" } // 700ms advance beat

        // Retest of fork: options reshuffle (variant bumped on first leave)…
        #expect(c.current?.word.id == "w-fork")
        #expect(c.isRetest)
        #expect(c.choicesVariant(for: queue[0]) == 1)
        // …a correct answer flash-advances with NO rating step…
        c.pick("fork")
        #expect(c.flash == .retestPassed)
        #expect(c.revealMode == nil)
        #expect(c.passedCount == 2)

        // …and the session wrote exactly two answers: fork's 重來 and cup's
        // auto 熟練 — nothing for the retest. Same generous ceiling as
        // waitUntil: the drain returns as soon as both writes land.
        await c.writes.drainPendingWrites(within: .seconds(10))
        #expect(writer.answers.map(\.rating).sorted() == ["熟練", "重來"].sorted())
    }

    @Test
    func retestWrongShowsContinueOnlySheet() throws {
        let queue = try Array(self.makeQueue().prefix(1))
        let c = ReviewFlowCoordinator(queue: queue, writer: SpyAnswerWriter())
        // Force the retest state directly: mark as already retried.
        c.retriedIds.insert("w-fork")
        c.pick("spoon")
        #expect(c.revealMode == .continueOnly)
        #expect(c.passedCount == 1) // leaves the session either way
        #expect(c.rated == nil) // no write path taken
    }

    @Test
    func slowCorrectStillAsksForManualRating() throws {
        let queue = try self.makeQueue()
        let c = ReviewFlowCoordinator(queue: queue, writer: SpyAnswerWriter())
        // Simulate a slow answer by backdating the item start.
        c.startedAt = Date(timeIntervalSinceNow: -10)
        c.pick("fork")
        #expect(c.revealMode == .rate)
        #expect(c.suggested == .hard)
        #expect(c.availableRatings == [.hard, .good, .easy])
    }

    // MARK: - 求救提示 (hint flip)

    @Test
    func suggestionCapsHintedAnswersAtHard() throws {
        let queue = try self.makeQueue()
        let c = ReviewFlowCoordinator(queue: queue, writer: SpyAnswerWriter())
        // Speed and mastery stop mattering once the gloss was read.
        #expect(c.computeSuggestion(correct: true, elapsed: 1, mastery: 80, hinted: true) == .hard)
        #expect(c.computeSuggestion(correct: true, elapsed: 5, mastery: 80, hinted: true) == .hard)
        // Wrong is still 重來 — the hint cannot make a miss look better.
        #expect(c.computeSuggestion(correct: false, elapsed: 1, mastery: 80, hinted: true) == .again)
    }

    /// The load-bearing one. Nothing in `pick()` mentions the hint: the auto-rate
    /// branch requires a suggestion other than 困難, and capping a hinted answer
    /// at 困難 is what switches it off. If someone later relaxes the cap, the
    /// sheet silently stops appearing — this test is the tripwire.
    @Test
    func hintedCorrectRaisesSheetInsteadOfAutoRating() throws {
        let queue = try self.makeQueue()
        let c = ReviewFlowCoordinator(queue: queue, writer: SpyAnswerWriter())
        c.toggleHint()
        #expect(c.hintFaceUp)
        #expect(c.hinted)
        // Answered immediately and correctly — without the hint this would have
        // auto-rated 穩定 and flash-advanced.
        c.pick("fork")
        #expect(c.revealMode == .rate)
        #expect(c.flash == nil)
        #expect(c.rated == nil)
        #expect(c.suggested == .hard)
        #expect(c.availableRatings == [.again, .hard])
    }

    @Test
    func hintedCorrectDoesNotRequeue() throws {
        let queue = try self.makeQueue()
        let c = ReviewFlowCoordinator(queue: queue, writer: SpyAnswerWriter())
        c.toggleHint()
        c.pick("fork")
        // 重來 is offered on a hinted answer, but requeueing still keys off
        // "did they pick the wrong option", which they did not.
        c.rate(.again)
        #expect(c.queue.map(\.word.id) == ["w-fork", "w-cup"])
        #expect(c.retriedIds.isEmpty)
        #expect(c.passedCount == 1)
    }

    @Test
    func hintedWrongMatchesThePlainWrongPath() throws {
        let queue = try self.makeQueue()
        let c = ReviewFlowCoordinator(queue: queue, writer: SpyAnswerWriter())
        c.toggleHint()
        c.pick("spoon")
        #expect(c.suggested == .again)
        #expect(c.availableRatings == [.again, .hard])
        c.rate(.again)
        #expect(c.queue.map(\.word.id) == ["w-fork", "w-cup", "w-fork"])
        #expect(c.retriedIds.contains("w-fork"))
    }

    @Test
    func hintStaysSeenAfterFlippingBack() throws {
        let queue = try self.makeQueue()
        let c = ReviewFlowCoordinator(queue: queue, writer: SpyAnswerWriter())
        c.toggleHint()
        c.toggleHint()
        #expect(!c.hintFaceUp) // showing the picture again…
        #expect(c.hinted) // …but the gloss cannot be un-seen
        #expect(!c.canNudge)
    }

    @Test
    func hintIsLockedOnceAnswered() throws {
        let queue = try self.makeQueue()
        let c = ReviewFlowCoordinator(queue: queue, writer: SpyAnswerWriter())
        // The reveal sheet rests at a detent that leaves the hero tappable, so
        // an answered item must refuse the flip rather than rewrite its rating.
        c.pick("fork")
        c.toggleHint()
        #expect(!c.hintFaceUp)
        #expect(!c.hinted)
        #expect(!c.canNudge)
    }

    @Test
    func hintResetsOnAdvance() async throws {
        let queue = try self.makeQueue()
        let c = ReviewFlowCoordinator(queue: queue, writer: SpyAnswerWriter(), beat: { _ in })
        c.toggleHint()
        c.pick("fork")
        c.rate(.hard)
        try await self.waitUntil { c.current?.word.id == "w-cup" } // 300ms beat
        #expect(!c.hinted)
        #expect(!c.hintFaceUp)
        #expect(c.canNudge)
    }

    @Test
    func hintedFlagReachesThePayload() async throws {
        let queue = try self.makeQueue()
        let writer = SpyAnswerWriter()
        let c = ReviewFlowCoordinator(queue: queue, writer: writer)
        c.toggleHint()
        c.pick("fork")
        c.rate(.hard)
        await c.writes.drainPendingWrites(within: .seconds(10))
        #expect(writer.answers.map(\.hinted) == [true])
        #expect(writer.answers.map(\.rating) == ["困難"])
    }

    @Test
    func plainAnswerReportsNotHinted() async throws {
        let queue = try self.makeQueue()
        let writer = SpyAnswerWriter()
        let c = ReviewFlowCoordinator(queue: queue, writer: writer)
        c.pick("fork")
        await c.writes.drainPendingWrites(within: .seconds(10))
        #expect(writer.answers.map(\.hinted) == [false])
    }

    @Test
    func retestFlipIsFree() async throws {
        let queue = try Array(self.makeQueue().prefix(1))
        let writer = SpyAnswerWriter()
        let c = ReviewFlowCoordinator(queue: queue, writer: writer)
        c.retriedIds.insert("w-fork")
        // A retest never writes SRS, so there is nothing for the hint to cost.
        #expect(!c.canNudge)
        c.toggleHint()
        c.pick("fork")
        #expect(c.flash == .retestPassed)
        #expect(c.revealMode == nil)
        #expect(c.rated == nil)
        await c.writes.drainPendingWrites(within: .seconds(2))
        #expect(writer.answers.isEmpty)
    }

    // MARK: - 再來一輪 (another round)

    @Test
    func fetchAnotherRoundReturnsTheProviderQueue() async throws {
        let queue = try self.makeQueue()
        let provider = FakeQueueProvider()
        provider.result = .success(queue)
        let c = ReviewFlowCoordinator(queue: [], writer: SpyAnswerWriter(), queueProvider: provider)

        let next = await c.fetchAnotherRound()

        #expect(next.map(\.word.id) == queue.map(\.word.id))
        #expect(provider.fetched == [.review])
    }

    @Test
    func fetchAnotherRoundReturnsEmptyOnFailure() async {
        let provider = FakeQueueProvider()
        provider.result = .failure(RoundError.boom)
        let c = ReviewFlowCoordinator(queue: [], writer: SpyAnswerWriter(), queueProvider: provider)

        let next = await c.fetchAnotherRound()

        #expect(next.isEmpty)
    }

    // MARK: - 先離開 during the advance beat

    /// 學新字 has carried `cancelPendingBeats` for a while, and the comment on
    /// `NewFlowCoordinator.recognizeAnswer` records that the guarantee had been
    /// declared complete once while one of its three stages still leaked. 複習
    /// was a fourth copy of that stage in the other flow, and it had no array to
    /// cancel at all: `scheduleAdvance` spawned an untracked `Task`, so leaving
    /// mid-answer still ran `advance()` on a coordinator whose screen was gone —
    /// draining writes and flipping `finished` behind a dismissed view.
    @Test
    func leavingDuringTheAdvanceBeatDoesNotFinishTheSession() async throws {
        let queue = try Array(self.makeQueue().prefix(1))
        let c = ReviewFlowCoordinator(queue: queue, writer: SpyAnswerWriter(), beat: { _ in
            // Long enough that the cancellation lands first.
            try? await Task.sleep(for: .milliseconds(200))
        })

        c.pick("fork") // fast + correct ⇒ auto-rate ⇒ scheduleAdvance
        c.cancelPendingBeats()
        try? await Task.sleep(for: .milliseconds(300))

        #expect(!c.finished)
    }

    /// The control: without the cancel, the same beat must still land. A guard
    /// that swallows every advance would pass the test above.
    @Test
    func theAdvanceBeatFinishesTheSessionWhenItIsNotCancelled() async throws {
        let queue = try Array(self.makeQueue().prefix(1))
        let c = ReviewFlowCoordinator(queue: queue, writer: SpyAnswerWriter(), beat: { _ in })

        c.pick("fork")
        // `advance()` drains writes before flipping `finished`, so poll rather
        // than sleep a fixed span — CI runs these suites in parallel on one actor.
        for _ in 0..<120 where !c.finished {
            try? await Task.sleep(for: .milliseconds(50))
        }

        #expect(c.finished)
    }

    /// Cancelling mid-queue must not advance to the next item either — the
    /// single-item case above only proves the `finished` branch.
    @Test
    func leavingDuringTheAdvanceBeatDoesNotMoveToTheNextItem() async throws {
        let queue = try self.makeQueue() // two items
        let c = ReviewFlowCoordinator(queue: queue, writer: SpyAnswerWriter(), beat: { _ in
            try? await Task.sleep(for: .milliseconds(200))
        })
        let before = c.current?.word.id

        c.pick("fork")
        c.cancelPendingBeats()
        try? await Task.sleep(for: .milliseconds(300))

        #expect(c.current?.word.id == before)
    }
}

private enum RoundError: Error { case boom }

@MainActor
private final class FakeQueueProvider: StudyQueueProviding {
    var result: Result<[StudyQueueItem], Error> = .success([])
    /// A queue already warm in the cache. nil = the caller must fetch.
    var warm: [StudyQueueItem]?
    private(set) var fetched: [StudyMode] = []
    private(set) var taken: [StudyMode] = []

    func fetch(mode: StudyMode) async throws -> [StudyQueueItem] {
        self.fetched.append(mode)
        return try self.result.get()
    }

    func take(mode: StudyMode) -> [StudyQueueItem]? {
        self.taken.append(mode)
        defer { self.warm = nil }
        return self.warm
    }
}

/// Records submitted answers and returns a configurable outcome. Defaults to a
/// `.synced` response with a canned mastery delta; set `outcome = .parked` to
/// exercise the offline path.
@MainActor
private final class SpyAnswerWriter: DurableAnswerWriting {
    private(set) var answers: [StudyAnswerPayload] = []
    var outcome: StudyWriteOutcome = .synced(
        StudyAnswerResponse(
            ok: true,
            milestone: nil,
            mastery: MasteryDelta(before: 10, after: 20, delta: 10)
        )
    )

    func submitAnswer(_ payload: StudyAnswerPayload) async -> StudyWriteOutcome {
        self.answers.append(payload)
        return self.outcome
    }
}
