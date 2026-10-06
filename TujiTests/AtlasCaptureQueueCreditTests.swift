// 生成佇列's 罐頭點數 kind: 確認並生成卡片 closes the sheet at once and the card
// is made here, behind a 生成中 tile in 我做的. What differs from the free flow is
// pinned below — the confirm is the operation's (and safe to resend), and the
// server fills the card in on its own, so the job waits for that instead of
// calling enrich.

import Foundation
import Testing
@testable import Tuji

@MainActor
struct AtlasCaptureQueueCreditTests {
    private func queue(
        cards: FakeCardGenerating = FakeCardGenerating(),
        credits: FakeCreditConfirming = FakeCreditConfirming(),
        journal: InMemoryCaptureJobJournal = InMemoryCaptureJobJournal(),
        mutations: SpyAtlasMutationRefreshing = SpyAtlasMutationRefreshing(),
        deadline: Duration = .seconds(5)
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
        // Its slot was reserved server-side at acceptance; counting it here too
        // would close the gate one card early.
        #expect(queue.inFlightCount == 0)
        await task.value

        #expect(credits.confirmed == [self.request])
        #expect(cards.confirmedImageIds.isEmpty)
        #expect(cards.generatedItemIds == ["item-1"])
        // The server fills the card in; the client must not also call enrich.
        #expect(cards.enrichedItemIds.isEmpty)
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
        // The previous session died after confirm; the journal says so.
        var record = CaptureJobRecord(
            id: UUID(),
            imageId: "img-1",
            payload: nil,
            lemma: "鏡",
            itemId: "item-1",
            credit: self.request
        )
        record.itemId = "item-1"
        let cards = FakeCardGenerating()
        let credits = FakeCreditConfirming()
        let queue = self.queue(
            cards: cards,
            credits: credits,
            journal: InMemoryCaptureJobJournal([CaptureJobEntry(record: record, thumbnail: nil)])
        )

        await queue.settle()

        // Unlike the free flow's INSERT, the server returns the card it already bound.
        #expect(credits.confirmed == [self.request])
        #expect(cards.confirmedImageIds.isEmpty)
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
    func aRecordJournalledBeforeCreditJobsExistedStillDecodesAsAFreeFlowJob() throws {
        // Exactly what a shipped build wrote: no `credit` key.
        let json = """
        {"id":"6F9619FF-8B86-D011-B42D-00C04FC964FF","imageId":"img-1","lemma":"cat","itemId":"item-1",
         "payload":{"primaryLabel":"cat","lemma":"cat","displayZhHant":"貓"}}
        """
        let record = try JSONDecoder().decode(CaptureJobRecord.self, from: Data(json.utf8))
        #expect(record.credit == nil)
        #expect(record.payload?.lemma == "cat")
        #expect(record.itemId == "item-1")
    }

    @Test
    func aResultTheQueueIsConfirmingIsNotReopenedIn拍照新增() {
        let waiting = CreditOperation(
            id: "op-1", state: "committed", feature: "atlas.recognize.primary", targetLanguage: "ja",
            imageId: "img-1", points: 100, confirmedItemId: nil, fulfillmentState: "unclaimed", result: nil
        )
        #expect(CreditCaptureModel.resumable(in: [waiting])?.id == "op-1")
        #expect(CreditCaptureModel.resumable(in: [waiting], queued: ["op-1"]) == nil)
    }
}
