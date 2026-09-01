// Pins the durable-write policy now that it lives in one place: succeed on the
// first try, retry then succeed, or exhaust all attempts and park. The retry
// backoff (400ms, 800ms) is real, so the park test awaits the actual result —
// no fixed-deadline poll, so it can't flake, only take its bounded time.

import Foundation
import Testing
@testable import Tuji

@MainActor
struct DurableAnswerWriterTests {
    private func makeOutbox() -> StudyAnswerOutbox {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("writer-outbox-\(UUID().uuidString).json")
        let owner = UUID(uuidString: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa")!
        return StudyAnswerOutbox(fileURL: url, activeUserID: { owner })
    }

    private func payload(card: String = "c1") -> StudyAnswerPayload {
        StudyAnswerPayload(cardId: card, rating: .good, responseMs: 900, activity: "mcq")
    }

    @Test
    func syncsOnFirstTryWithoutParking() async {
        let repo = StubStudyRepository()
        let outbox = self.makeOutbox()
        let writer = DurableAnswerWriter(repository: repo, outbox: outbox)

        let outcome = await writer.submitAnswer(self.payload())

        guard case let .synced(resp) = outcome else {
            Issue.record("expected .synced, got \(outcome)")
            return
        }
        #expect(resp.mastery?.delta == 5)
        #expect(repo.callCount == 1)
        #expect(outbox.pending.isEmpty)
    }

    @Test
    func retriesThenSyncs() async {
        let repo = StubStudyRepository(failuresBeforeSuccess: 1)
        let outbox = self.makeOutbox()
        let writer = DurableAnswerWriter(repository: repo, outbox: outbox)

        let outcome = await writer.submitAnswer(self.payload())

        guard case .synced = outcome else {
            Issue.record("expected .synced after a retry, got \(outcome)")
            return
        }
        #expect(repo.callCount == 2)
        #expect(outbox.pending.isEmpty)
    }

    @Test
    func parksAfterExhaustingRetries() async {
        let repo = StubStudyRepository(alwaysFail: true)
        let outbox = self.makeOutbox()
        let writer = DurableAnswerWriter(repository: repo, outbox: outbox)

        let outcome = await writer.submitAnswer(self.payload(card: "c9"))

        guard case .parked = outcome else {
            Issue.record("expected .parked, got \(outcome)")
            return
        }
        #expect(repo.callCount == 3) // three attempts, then give up
        #expect(outbox.pending.map(\.cardId) == ["c9"])
    }
}

/// A raw study repository whose `submitAnswer` fails a set number of times
/// (or always), then returns a canned response. Only `submitAnswer` is exercised
/// by the writer; the rest throw.
@MainActor
private final class StubStudyRepository: StudyRepository {
    let failuresBeforeSuccess: Int
    let alwaysFail: Bool
    private(set) var callCount = 0

    struct Boom: Error {}
    struct NotImplemented: Error {}

    init(failuresBeforeSuccess: Int = 0, alwaysFail: Bool = false) {
        self.failuresBeforeSuccess = failuresBeforeSuccess
        self.alwaysFail = alwaysFail
    }

    func loadQueue(mode _: StudyMode, limit _: Int, newCount _: Int, categories _: [String]) async throws
        -> StudyQueueResponse
    {
        throw NotImplemented()
    }

    func loadStats() async throws -> StudyStatsResponse {
        throw NotImplemented()
    }

    func submitAnswer(_: StudyAnswerPayload) async throws -> StudyAnswerResponse {
        self.callCount += 1
        if self.alwaysFail || self.callCount <= self.failuresBeforeSuccess { throw Boom() }
        return StudyAnswerResponse(
            ok: true,
            milestone: nil,
            mastery: MasteryDelta(before: 10, after: 15, delta: 5)
        )
    }

    func submitReport(_: StudyReportPayload) async throws {
        throw NotImplemented()
    }
}
