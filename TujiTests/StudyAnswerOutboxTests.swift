// Pins the durable answer outbox: park → survive a "relaunch" (new instance,
// same file) → replay clears on success and holds on failure.

import Foundation
import Testing
@testable import Tuji

@MainActor
struct StudyAnswerOutboxTests {
    private let ownerA = UUID(uuidString: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa")!
    private let ownerB = UUID(uuidString: "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb")!

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
        let outbox = StudyAnswerOutbox(fileURL: url, activeUserID: { self.ownerA })
        outbox.add(self.payload(card: "c1"))
        outbox.add(self.payload(card: "c2"))
        // "Relaunch": a fresh instance over the same file sees both.
        let reloaded = StudyAnswerOutbox(fileURL: url, activeUserID: { self.ownerA })
        #expect(reloaded.pending.map(\.cardId) == ["c1", "c2"])
        #expect(reloaded.pending.first?.rating == "重來")
    }

    @Test
    func replayClearsOnSuccess() async {
        let url = self.tempURL()
        let outbox = StudyAnswerOutbox(fileURL: url, activeUserID: { self.ownerA })
        outbox.add(self.payload(card: "c1"))
        outbox.add(self.payload(card: "c2"))
        let repo = OutboxSpyRepository(failing: false)
        await outbox.replay(using: repo)
        #expect(outbox.pending.isEmpty)
        #expect(repo.answers.map(\.cardId) == ["c1", "c2"])
        #expect(repo.answers.allSatisfy { $0.ownerUserId == self.ownerA })
        // The emptied state persisted too.
        #expect(StudyAnswerOutbox(fileURL: url, activeUserID: { self.ownerA }).pending.isEmpty)
    }

    /// A pre-account-binding payload has no safe owner. It is quarantined
    /// rather than replayed under the next signed-in account.
    @Test
    func unownedLegacyAnswersAreQuarantined() throws {
        let legacy = """
        [{ "cardId": "c1", "rating": "重來", "responseMs": 1234, "activity": "mcq" }]
        """
        let url = self.tempURL()
        try Data(legacy.utf8).write(to: url)
        let outbox = StudyAnswerOutbox(fileURL: url, activeUserID: { self.ownerA })
        #expect(outbox.pending.isEmpty)
        #expect(FileManager.default.fileExists(atPath: url.appendingPathExtension("unowned").path))
    }

    @Test
    func replayHoldsEverythingWhenOffline() async {
        let url = self.tempURL()
        let outbox = StudyAnswerOutbox(fileURL: url, activeUserID: { self.ownerA })
        outbox.add(self.payload(card: "c1"))
        outbox.add(self.payload(card: "c2"))
        let repo = OutboxSpyRepository(failing: true)
        await outbox.replay(using: repo)
        // First failure stops the pass; nothing is lost.
        #expect(outbox.count == 2)
    }

    @Test
    func answersNeverReplayUnderAnotherAccount() async {
        let url = self.tempURL()
        var activeOwner = self.ownerA
        let outbox = StudyAnswerOutbox(fileURL: url, activeUserID: { activeOwner })
        outbox.add(self.payload(card: "a-card"))
        activeOwner = self.ownerB

        let repo = OutboxSpyRepository(failing: false)
        await outbox.replay(using: repo)

        #expect(repo.answers.isEmpty)
        #expect(outbox.pending.isEmpty)
        let ownerView = StudyAnswerOutbox(fileURL: url, activeUserID: { self.ownerA })
        #expect(ownerView.pending.map(\.cardId) == ["a-card"])
    }

    @Test
    func accountChangeDuringReplayCannotRemoveAnotherSessionsState() async {
        let url = self.tempURL()
        var activeOwner = self.ownerA
        let outbox = StudyAnswerOutbox(fileURL: url, activeUserID: { activeOwner })
        outbox.add(self.payload(card: "a-card"))
        let repo = OutboxSpyRepository(failing: false)
        repo.onSubmit = { _ in
            activeOwner = self.ownerB
            outbox.reset()
        }

        await outbox.replay(using: repo)

        #expect(outbox.pending.isEmpty)
        #expect(repo.answers.first?.ownerUserId == self.ownerA)
    }

    @Test
    func resetClearsAndPersistsTheAccountBoundary() {
        let url = self.tempURL()
        let outbox = StudyAnswerOutbox(fileURL: url, activeUserID: { self.ownerA })
        outbox.add(self.payload(card: "c1"))

        outbox.reset()

        #expect(outbox.pending.isEmpty)
        #expect(StudyAnswerOutbox(fileURL: url, activeUserID: { self.ownerA }).pending.isEmpty)
    }
}

@MainActor
private final class OutboxSpyRepository: StudyRepository {
    let failing: Bool
    private(set) var answers: [StudyAnswerPayload] = []
    var onSubmit: ((StudyAnswerPayload) -> Void)?

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
        self.onSubmit?(payload)
        return StudyAnswerResponse(ok: true, milestone: nil, mastery: nil)
    }

    func submitReport(_: StudyReportPayload) async throws {
        throw NotImplemented()
    }
}
