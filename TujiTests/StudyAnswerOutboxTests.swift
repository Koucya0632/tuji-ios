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
extension StudyAnswerOutboxTests {
    /// A permanently refused answer (404 card gone, 403, 402…) used to stay at
    /// the head of the outbox and stop every pass, so nothing queued behind it
    /// was ever sent again. It is dropped now, and the pass carries on.
    @Test
    func permanentlyRefusedAnswerIsDroppedAndReplayContinues() async {
        let url = self.tempURL()
        let outbox = StudyAnswerOutbox(fileURL: url, activeUserID: { self.ownerA })
        outbox.add(self.payload(card: "gone"))
        outbox.add(self.payload(card: "c2"))
        let repo = OutboxSpyRepository(failing: false)
        repo.errorsByCard["gone"] = APIError.notFound
        await outbox.replay(using: repo)
        #expect(outbox.pending.isEmpty)
        #expect(repo.answers.map(\.cardId) == ["c2"])
    }

    /// A transient failure (offline, 5xx, 429, 401) still stops the pass and
    /// keeps everything — that half of the contract is unchanged.
    @Test
    func transientFailureStillStopsAndKeepsEverything() async {
        let url = self.tempURL()
        let outbox = StudyAnswerOutbox(fileURL: url, activeUserID: { self.ownerA })
        outbox.add(self.payload(card: "c1"))
        outbox.add(self.payload(card: "c2"))
        let repo = OutboxSpyRepository(failing: false)
        repo.errorsByCard["c1"] = APIError.server(status: 503, body: nil)
        await outbox.replay(using: repo)
        #expect(outbox.pending.map(\.cardId) == ["c1", "c2"])
    }
}

struct AnswerWriteFailureTests {
    @Test(arguments: [
        APIError.notFound, .forbidden, .paymentRequired(message: nil),
        .conflict(reason: nil, message: nil), .server(status: 400, body: nil),
        .server(status: 422, body: nil)
    ] as [APIError])
    func permanent(_ error: APIError) {
        #expect(AnswerWriteFailure.isPermanent(error))
    }

    @Test(arguments: [
        APIError.unauthorized, .rateLimited(message: nil), .server(status: 500, body: nil),
        .server(status: 503, body: nil), .server(status: 408, body: nil),
        .transport(URLError(.notConnectedToInternet)), .missingBaseURL,
    ] as [APIError])
    func transient(_ error: APIError) {
        #expect(!AnswerWriteFailure.isPermanent(error))
    }

    @Test
    func unknownErrorsAreTransient() {
        struct Mystery: Error {}
        #expect(!AnswerWriteFailure.isPermanent(Mystery()))
    }
}

private final class OutboxSpyRepository: StudyRepository {
    let failing: Bool
    private(set) var answers: [StudyAnswerPayload] = []
    var onSubmit: ((StudyAnswerPayload) -> Void)?
    /// Per-card error to throw instead of accepting, e.g. a permanent 404.
    var errorsByCard: [String: Error] = [:]

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
        if let error = self.errorsByCard[payload.cardId] { throw error }
        self.answers.append(payload)
        self.onSubmit?(payload)
        return StudyAnswerResponse(ok: true, milestone: nil, mastery: nil)
    }

    func submitReport(_: StudyReportPayload) async throws {
        throw NotImplemented()
    }
}
