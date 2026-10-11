// 生成佇列: 確認並生成卡片 closes the sheet at once and the card is made here,
// behind a 生成中 tile in 我做的. Pinned below — the confirm is the operation's
// (so a resumed or retried job simply runs again), the server fills the card in
// on its own and the job waits for that, and a sign-out leaves nothing behind.

import Foundation
import Testing
import UIKit
@testable import Tuji

@MainActor
struct AtlasCaptureQueueTests {
    private func queue(
        cards: FakeCardGenerating = FakeCardGenerating(),
        credits: FakeCreditConfirming = FakeCreditConfirming(),
        journal: InMemoryCaptureJobJournal = InMemoryCaptureJobJournal(),
        mutations: SpyAtlasMutationRefreshing = SpyAtlasMutationRefreshing(),
        // Generous on purpose: parallel @MainActor suites starve each other on
        // CI for well over 5s, and a deadline that passes mid-test turns a
        // "waits for the fill-in" assertion into a timing coin flip.
        deadline: Duration = .seconds(60)
    )
        -> AtlasCaptureQueue
    {
        AtlasCaptureQueue(
            cards: cards,
            credits: credits,
            journal: journal,
            mutations: mutations,
            doneLinger: .zero,
            enrichmentPoll: .milliseconds(1),
            enrichmentDeadline: deadline,
            celebrate: {}
        )
    }

    private let request = CreditConfirmRequest(
        operationId: "op-1",
        candidateId: "cand-1",
        lemma: "鏡",
        displayZhHant: "鏡子",
        displayGloss: nil
    )

    @Test
    func aCreditCaptureConfirmsMakesCardsWaitsForTheFillInThenFinishes() async {
        let cards = FakeCardGenerating()
        let credits = FakeCreditConfirming()
        credits.fillIn = ["running", "completed"]
        let journal = InMemoryCaptureJobJournal()
        let mutations = SpyAtlasMutationRefreshing()
        let queue = self.queue(cards: cards, credits: credits, journal: journal, mutations: mutations)

        let task = queue.enqueue(credit: self.request, imageId: "img-1", thumbnail: nil)
        // The tile is up before any network work: this is what the sheet closes onto.
        #expect(queue.jobs.first?.lemma == "鏡")
        #expect(queue.jobs.first?.progress == .generating(0.15))
        #expect(queue.creditOperationIds == ["op-1"])
        await task.value

        #expect(credits.confirmed == [self.request])
        #expect(cards.generatedItemIds == ["item-1"])
        #expect(credits.polls == 2)
        #expect(cards.reconciles == 1)
        #expect(mutations.reported == [.captureCompleted])
        #expect(journal.entries.isEmpty)
        #expect(queue.jobs.isEmpty)
    }

    @Test
    func aFillInAlreadyFinishedAtConfirmIsNotPolled() async {
        let credits = FakeCreditConfirming()
        credits.confirmState = "completed"
        let queue = self.queue(credits: credits)

        await queue.enqueue(credit: self.request, imageId: "img-1", thumbnail: nil).value

        #expect(credits.polls == 0)
        #expect(queue.jobs.isEmpty)
    }

    @Test
    func aFillInThatNeverEndsStillFinishesTheJobAtTheDeadline() async {
        let credits = FakeCreditConfirming()
        credits.fillIn = ["running"]
        let mutations = SpyAtlasMutationRefreshing()
        let queue = self.queue(credits: credits, mutations: mutations, deadline: .milliseconds(30))

        await queue.enqueue(credit: self.request, imageId: "img-1", thumbnail: nil).value

        // The card exists; a stuck fill-in must not hold the tile on 補充詳情中.
        #expect(credits.polls > 0)
        #expect(mutations.reported == [.captureCompleted])
        #expect(queue.jobs.isEmpty)
    }

    @Test
    func aResumedCreditJobResendsTheIdempotentConfirm() async {
        // The previous session died mid-job; the journal still holds it.
        let record = CaptureJobRecord(id: UUID(), imageId: "img-1", lemma: "鏡", credit: self.request)
        let cards = FakeCardGenerating()
        let credits = FakeCreditConfirming()
        let queue = self.queue(
            cards: cards,
            credits: credits,
            journal: InMemoryCaptureJobJournal([CaptureJobEntry(record: record, thumbnail: nil)])
        )

        await queue.settle()

        // No checkpoint to consult: the server returns the card it already bound.
        #expect(credits.confirmed == [self.request])
        #expect(cards.generatedItemIds == ["item-1"])
        #expect(queue.jobs.isEmpty)
    }

    @Test
    func aFullAtlasIsADeadEndAndANetworkErrorIsRetryable() async throws {
        let full = FakeCreditConfirming()
        full.confirmFailures = 1
        full.failureError = APIError.conflict(reason: "capacity_full", message: nil)
        let blocked = self.queue(credits: full)
        await blocked.enqueue(credit: self.request, imageId: "img-1", thumbnail: nil).value
        let dead = try #require(blocked.jobs.first)
        #expect(dead.progress == .failed(.atCapacity(nil)))
        #expect(!dead.progress.canRetry)

        let flaky = FakeCreditConfirming()
        flaky.confirmFailures = 1
        let journal = InMemoryCaptureJobJournal()
        let retrying = self.queue(credits: flaky, journal: journal)
        await retrying.enqueue(credit: self.request, imageId: "img-1", thumbnail: nil).value
        let job = try #require(retrying.jobs.first)
        #expect(job.progress.canRetry)
        // The record survives so an app kill can still resume it.
        #expect(journal.restore().first?.record.credit == self.request)
        await retrying.retry(job.id)?.value
        #expect(flaky.confirmed == [self.request])
        #expect(retrying.jobs.isEmpty)
    }

    @Test
    func aFailedJobKeepsTheFrameTheUserTook() async throws {
        let cards = FakeCardGenerating()
        cards.generateFailures = 1
        let journal = InMemoryCaptureJobJournal()
        let queue = self.queue(cards: cards, journal: journal)
        // A real 1×1 frame, so `enqueue` has something to JPEG-encode.
        let frame = UIGraphicsImageRenderer(size: CGSize(width: 1, height: 1)).image { context in
            UIColor.red.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 1, height: 1))
        }

        await queue.enqueue(credit: self.request, imageId: "img-1", thumbnail: frame).value

        // Without it a resumed tile shows an empty box under the user's word.
        let entry = try #require(journal.restore().first)
        #expect(entry.thumbnail != nil)
        #expect(queue.jobs.first?.progress.canRetry == true)
    }

    @Test
    func signOutDropsEveryJobAndItsRecord() async {
        let credits = FakeCreditConfirming()
        credits.confirmFailures = 1
        let journal = InMemoryCaptureJobJournal()
        let queue = self.queue(credits: credits, journal: journal)

        await queue.enqueue(credit: self.request, imageId: "img-1", thumbnail: nil).value
        queue.reset()

        // A journalled job survives app kills, so leaving one behind would resume
        // the previous account's capture under the next account's session.
        #expect(queue.jobs.isEmpty)
        #expect(journal.entries.isEmpty)
    }

    @Test
    func aRecordFromThePreCreditFlowIsClearedAwayRatherThanResumed() throws {
        // Exactly what a shipped build wrote for the retired flow: no `credit`.
        // The server refuses its confirm now, so resuming it could only fail.
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("capture-journal-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let journal = FileCaptureJobJournal(directory: directory)
        let stale = directory.appendingPathComponent("6F9619FF-8B86-D011-B42D-00C04FC964FF.json")
        try Data("""
        {"id":"6F9619FF-8B86-D011-B42D-00C04FC964FF","imageId":"img-1","lemma":"cat","itemId":"item-1",
         "payload":{"primaryLabel":"cat","lemma":"cat","displayZhHant":"貓"}}
        """.utf8).write(to: stale)
        let kept = CaptureJobRecord(id: UUID(), imageId: "img-2", lemma: "鏡", credit: self.request)
        journal.save(kept, thumbnail: nil)

        #expect(journal.restore().map(\.record) == [kept])
        // Left on disk it would be read and skipped on every launch, forever.
        #expect(!FileManager.default.fileExists(atPath: stale.path))
    }

    @Test
    func aResultTheQueueIsConfirmingIsNotReopenedIn拍照新增() {
        let waiting = CreditOperation(
            id: "op-1", state: "committed", feature: "atlas.recognize.primary", targetLanguage: "ja",
            imageId: "img-1", points: 100, confirmedItemId: nil, fulfillmentState: "unclaimed", result: nil
        )
        #expect(CreditOperation.resumable(in: [waiting])?.id == "op-1")
        #expect(CreditOperation.resumable(in: [waiting], queued: ["op-1"]) == nil)
    }
}
