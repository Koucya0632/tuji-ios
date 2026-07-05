// Pins the review answer paths: fast-correct auto-rating (with the
// mastery-capped suggestion), the wrong-answer restricted ratings + requeue,
// and the retest contract — reshuffled options, no second SRS write. The
// advance beats are real (300-800ms) Tasks, so the end-to-end test sleeps
// through them; everything else asserts synchronously.

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

    private func makeOutbox() -> StudyAnswerOutbox {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("outbox-\(UUID().uuidString).json")
        return StudyAnswerOutbox(fileURL: url)
    }

    @Test
    func suggestionCapsEasyForLowMastery() throws {
        let queue = try self.makeQueue()
        let c = ReviewFlowCoordinator(queue: queue, outbox: self.makeOutbox())
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
        let spy = SpyReviewRepository()
        let c = ReviewFlowCoordinator(queue: queue, repository: spy, outbox: self.makeOutbox())
        c.pick("fork")
        // No sheet, flash capsule instead, suggested applied (mastery 10 → 穩定).
        #expect(c.revealMode == nil)
        #expect(c.flash == .autoRated(.good))
        #expect(c.rated == .good)
        #expect(c.passedCount == 1)
        await c.drainPendingWrites(within: .seconds(2))
        #expect(spy.answers.map(\.rating) == ["穩定"])
        #expect(spy.answers.first?.responseMs != nil)
    }

    @Test
    func wrongAnswerRestrictsRatingsAndRequeues() throws {
        let queue = try self.makeQueue()
        let c = ReviewFlowCoordinator(queue: queue, outbox: self.makeOutbox())
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
        let spy = SpyReviewRepository()
        let c = ReviewFlowCoordinator(queue: queue, repository: spy, outbox: self.makeOutbox())

        // Item 1 (fork): wrong → manual 重來 → requeued.
        c.pick("spoon")
        c.rate(.again)
        try await Task.sleep(for: .milliseconds(500)) // 300ms advance beat
        #expect(c.current?.word.id == "w-cup")

        // Item 2 (cup): fast correct → auto-rated (mastery 80 → 熟練).
        c.pick("cup")
        #expect(c.flash == .autoRated(.easy))
        try await Task.sleep(for: .milliseconds(900)) // 700ms advance beat

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
        // auto 熟練 — nothing for the retest.
        await c.drainPendingWrites(within: .seconds(2))
        #expect(spy.answers.map(\.rating).sorted() == ["熟練", "重來"].sorted())
    }

    @Test
    func retestWrongShowsContinueOnlySheet() throws {
        let queue = try Array(self.makeQueue().prefix(1))
        let c = ReviewFlowCoordinator(queue: queue, outbox: self.makeOutbox())
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
        let c = ReviewFlowCoordinator(queue: queue, outbox: self.makeOutbox())
        // Simulate a slow answer by backdating the item start.
        c.startedAt = Date(timeIntervalSinceNow: -10)
        c.pick("fork")
        #expect(c.revealMode == .rate)
        #expect(c.suggested == .hard)
        #expect(c.availableRatings == [.hard, .good, .easy])
    }
}

/// Records submitted answers and returns a canned mastery delta.
@MainActor
private final class SpyReviewRepository: StudyRepository {
    private(set) var answers: [StudyAnswerPayload] = []

    struct NotImplemented: Error {}

    func loadQueue(mode _: StudyMode, limit _: Int, newCount _: Int, categories _: [String]) async throws
        -> StudyQueueResponse
    {
        throw NotImplemented()
    }

    func loadStats() async throws -> StudyStatsResponse {
        throw NotImplemented()
    }

    func submitAnswer(_ payload: StudyAnswerPayload) async throws -> StudyAnswerResponse {
        self.answers.append(payload)
        return StudyAnswerResponse(
            ok: true,
            milestone: nil,
            mastery: MasteryDelta(before: 10, after: 20, delta: 10)
        )
    }

    func submitAnswerBestEffort(_ payload: StudyAnswerPayload) async {
        self.answers.append(payload)
    }

    func submitReport(_: StudyReportPayload) async throws {
        throw NotImplemented()
    }
}
