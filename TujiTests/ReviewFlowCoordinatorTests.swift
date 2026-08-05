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
        return try JSONDecoder().decode([StudyQueueItem].self, from: Data(json.utf8))
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
        let c = ReviewFlowCoordinator(queue: queue, writer: writer)
        c.pick("fork")
        // No sheet, flash capsule instead, suggested applied (mastery 10 → 穩定).
        #expect(c.revealMode == nil)
        #expect(c.flash == .autoRated(.good))
        #expect(c.rated == .good)
        #expect(c.passedCount == 1)
        await c.drainPendingWrites(within: .seconds(2))
        #expect(writer.answers.map(\.rating) == ["穩定"])
        #expect(writer.answers.first?.responseMs != nil)
        // The .synced response's mastery delta folds into the session summary.
        #expect(c.masteryByWord["w-fork"]?.after == 20)
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
        await c.drainPendingWrites(within: .seconds(2))
        #expect(writer.answers.count == 1)
        #expect(c.unsyncedCount == 1)
        #expect(c.masteryByWord["w-fork"] == nil)
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
        let c = ReviewFlowCoordinator(queue: queue, writer: writer)

        // Item 1 (fork): wrong → manual 重來 → requeued.
        c.pick("spoon")
        c.rate(.again)
        try await self.waitUntil { c.current?.word.id == "w-cup" } // 300ms advance beat
        #expect(c.current?.word.id == "w-cup")

        // Item 2 (cup): fast correct → auto-rated (mastery 80 → 熟練).
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
        await c.drainPendingWrites(within: .seconds(10))
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
