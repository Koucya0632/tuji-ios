// Pins the durable answer outbox: park → survive a "relaunch" (new instance,
// same file) → replay clears on success and holds on failure.

import Foundation
import Testing
@testable import Tuji

@MainActor
struct StudyAnswerOutboxTests {
    private func tempURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("outbox-test-\(UUID().uuidString).json")
    }

    private func payload(card: String) -> StudyAnswerPayload {
        StudyAnswerPayload(cardId: card, rating: .again, responseMs: 1234, activity: "mcq")
    }

    @Test
    func parkedAnswersSurviveRelaunch() {
        let url = self.tempURL()
        let outbox = StudyAnswerOutbox(fileURL: url)
        outbox.add(self.payload(card: "c1"))
        outbox.add(self.payload(card: "c2"))
        // "Relaunch": a fresh instance over the same file sees both.
        let reloaded = StudyAnswerOutbox(fileURL: url)
        #expect(reloaded.pending.map(\.cardId) == ["c1", "c2"])
        #expect(reloaded.pending.first?.rating == "重來")
    }

    @Test
    func replayClearsOnSuccess() async {
        let url = self.tempURL()
        let outbox = StudyAnswerOutbox(fileURL: url)
        outbox.add(self.payload(card: "c1"))
        outbox.add(self.payload(card: "c2"))
        let repo = OutboxSpyRepository(failing: false)
        await outbox.replay(using: repo)
        #expect(outbox.pending.isEmpty)
        #expect(repo.answers.map(\.cardId) == ["c1", "c2"])
        // The emptied state persisted too.
        #expect(StudyAnswerOutbox(fileURL: url).pending.isEmpty)
    }

    @Test
    func replayHoldsEverythingWhenOffline() async {
        let url = self.tempURL()
        let outbox = StudyAnswerOutbox(fileURL: url)
        outbox.add(self.payload(card: "c1"))
        outbox.add(self.payload(card: "c2"))
        let repo = OutboxSpyRepository(failing: true)
        await outbox.replay(using: repo)
        // First failure stops the pass; nothing is lost.
        #expect(outbox.count == 2)
    }
}

@MainActor
private final class OutboxSpyRepository: StudyRepository {
    let failing: Bool
    private(set) var answers: [StudyAnswerPayload] = []

    struct Offline: Error {}
    struct NotImplemented: Error {}

    init(failing: Bool) {
        self.failing = failing
    }

    func loadQueue(mode _: StudyMode, limit _: Int, newCount _: Int, categories _: [String]) async throws
        -> StudyQueueResponse
    {
        throw NotImplemented()
    }

    func loadStats() async throws -> StudyStatsResponse {
        throw NotImplemented()
    }

    func submitAnswer(_ payload: StudyAnswerPayload) async throws -> StudyAnswerResponse {
        if self.failing { throw Offline() }
        self.answers.append(payload)
        return StudyAnswerResponse(ok: true, milestone: nil, mastery: nil)
    }

    func submitAnswerBestEffort(_ payload: StudyAnswerPayload) async {
        self.answers.append(payload)
    }

    func submitReport(_: StudyReportPayload) async throws {
        throw NotImplemented()
    }
}
