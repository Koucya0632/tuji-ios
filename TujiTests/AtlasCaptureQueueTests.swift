// 生成佇列's durable tail — the confirm checkpoint, the resume rule, retry, and
// what a sign-out drops. None of this could be reached before: the queue had a
// `private init`, reached `AtlasStore.shared` at four call sites and hard-coded
// its Application Support path, so the one rule standing between a resumed run
// and a duplicate 自製圖鑑 card was verified by nothing.

import Foundation
import Testing
import UIKit
@testable import Tuji

@MainActor
struct AtlasCaptureQueueTests {
    /// `doneLinger: .zero` everywhere: the four-second pause is how long a
    /// finished tile stays on screen, not part of the pipeline, and waiting it
    /// out in a test is how a suite starts timing out on CI.
    private func queue(
        cards: FakeCardGenerating = FakeCardGenerating(),
        journal: InMemoryCaptureJobJournal = InMemoryCaptureJobJournal(),
        mutations: SpyAtlasMutationRefreshing = SpyAtlasMutationRefreshing(),
        celebrate: @escaping @MainActor () -> Void = {}
    )
        -> AtlasCaptureQueue
    {
        AtlasCaptureQueue(
            cards: cards,
            journal: journal,
            mutations: mutations,
            doneLinger: .zero,
            celebrate: celebrate
        )
    }

    private func record(itemId: String? = nil) -> CaptureJobRecord {
        CaptureJobRecord(
            id: UUID(),
            imageId: "img-1",
            payload: AtlasFixtures.payload(),
            lemma: "cat",
            itemId: itemId
        )
    }

    /// A real 1×1 frame, so `enqueue` has something to JPEG-encode.
    private var frame: UIImage {
        UIGraphicsImageRenderer(size: CGSize(width: 1, height: 1)).image { context in
            UIColor.red.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 1, height: 1))
        }
    }

    @Test
    func aFinishedCaptureRunsTheWholeTailAndClearsItsRecord() async {
        let cards = FakeCardGenerating()
        let journal = InMemoryCaptureJobJournal()
        let mutations = SpyAtlasMutationRefreshing()
        var celebrated = false
        let queue = self.queue(
            cards: cards,
            journal: journal,
            mutations: mutations,
            celebrate: { celebrated = true }
        )

        await queue.enqueue(imageId: "img-1", payload: AtlasFixtures.payload(), thumbnail: nil).value

        #expect(cards.confirmedImageIds == ["img-1"])
        #expect(cards.generatedItemIds == ["item-1"])
        #expect(cards.enrichedItemIds == ["item-1"])
        // The reconcile is what makes the new card true for every other screen.
        #expect(cards.reconciles == 1)
        #expect(mutations.reported == [.captureCompleted])
        #expect(celebrated)
        // A finished job leaves nothing behind to resume.
        #expect(journal.entries.isEmpty)
        #expect(queue.jobs.isEmpty)
    }

    @Test
    func confirmIsCheckpointedBeforeTheIdempotentTail() async throws {
        // createCards fails, so the run dies *after* confirm has committed.
        let cards = FakeCardGenerating()
        cards.generateFailures = 1
        let journal = InMemoryCaptureJobJournal()
        let queue = self.queue(cards: cards, journal: journal)

        await queue.enqueue(imageId: "img-1", payload: AtlasFixtures.payload(), thumbnail: nil).value

        // The record survives, carrying the item confirm created.
        let entry = try #require(journal.restore().first)
        #expect(entry.record.itemId == "item-1")
        #expect(queue.jobs.first?.progress == .failed(.transient))
    }

    @Test
    func theCheckpointKeepsTheFrameTheUserTook() async throws {
        // The checkpoint re-saves the record with no thumbnail. The frame was
        // written at enqueue and must survive, or a resumed tile shows an empty
        // box under the user's word.
        let cards = FakeCardGenerating()
        cards.generateFailures = 1
        let journal = InMemoryCaptureJobJournal()
        let queue = self.queue(cards: cards, journal: journal)

        await queue.enqueue(
            imageId: "img-1",
            payload: AtlasFixtures.payload(),
            thumbnail: self.frame
        ).value

        let entry = try #require(journal.restore().first)
        #expect(entry.record.itemId == "item-1")
        #expect(entry.thumbnail != nil)
    }

    @Test
    func aResumedRunNeverConfirmsTwice() async {
        // What a previous session left behind: confirm succeeded, the tail did not.
        let cards = FakeCardGenerating()
        let journal = InMemoryCaptureJobJournal([
            CaptureJobEntry(record: self.record(itemId: "item-1"), thumbnail: nil)
        ])
        let queue = self.queue(cards: cards, journal: journal)

        await queue.settle()

        // confirm is a plain INSERT server-side; running it again is a duplicate card.
        #expect(cards.confirmedImageIds.isEmpty)
        #expect(cards.generatedItemIds == ["item-1"])
        #expect(journal.entries.isEmpty)
    }

    @Test
    func aResumedJobDoesNotWalkItsProgressBackToTheStart() async {
        // Restore builds the job; the task that runs it has not been given a turn
        // yet, so this observes exactly what a relaunch puts on screen first.
        let journal = InMemoryCaptureJobJournal([
            CaptureJobEntry(record: self.record(itemId: "item-1"), thumbnail: nil)
        ])
        let resumed = self.queue(journal: journal)
        #expect(resumed.jobs.first?.progress == .generating(0.5))
        await resumed.settle()

        // A job with no checkpoint has genuinely not started.
        let fresh = self.queue(journal: InMemoryCaptureJobJournal([
            CaptureJobEntry(record: self.record(), thumbnail: nil)
        ]))
        #expect(fresh.jobs.first?.progress == .generating(0.15))
        await fresh.settle()
    }

    @Test
    func retryResumesFromTheCheckpointRatherThanFromTheTop() async throws {
        let cards = FakeCardGenerating()
        cards.generateFailures = 1
        let queue = self.queue(cards: cards)

        await queue.enqueue(imageId: "img-1", payload: AtlasFixtures.payload(), thumbnail: nil).value
        let jobId = try #require(queue.jobs.first?.id)
        await queue.retry(jobId)?.value

        // One confirm across both runs; only the idempotent half repeated.
        #expect(cards.confirmedImageIds == ["img-1"])
        #expect(cards.generatedItemIds == ["item-1"])
        #expect(queue.jobs.isEmpty)
    }

    @Test
    func aSpentQuotaIsADeadEndRatherThanSomethingToRetry() async throws {
        let cards = FakeCardGenerating()
        cards.confirmFailures = 1
        cards.failureError = APIError.paymentRequired(message: "自製圖鑑已達上限")
        let queue = self.queue(cards: cards)

        await queue.enqueue(imageId: "img-1", payload: AtlasFixtures.payload(), thumbnail: nil).value

        let job = try #require(queue.jobs.first)
        #expect(job.progress == .failed(.atCapacity("自製圖鑑已達上限")))
        // The tile must not offer 重試: another attempt fails the same way. This
        // used to be one untyped `.failed`, so a dead end wore a retry's costume.
        #expect(job.progress.canRetry == false)
        #expect(queue.retry(job.id) == nil)
        // The server's own copy wins over the generic line.
        #expect(job.progress.label == "自製圖鑑已達上限")
    }

    @Test
    func anOrdinaryFailureKeepsItsRecordSoAnAppKillCanStillResumeIt() async throws {
        let cards = FakeCardGenerating()
        cards.confirmFailures = 1
        let journal = InMemoryCaptureJobJournal()
        let queue = self.queue(cards: cards, journal: journal)

        await queue.enqueue(imageId: "img-1", payload: AtlasFixtures.payload(), thumbnail: nil).value

        #expect(queue.jobs.first?.progress.canRetry == true)
        let entry = try #require(journal.restore().first)
        // Nothing confirmed, so there is no checkpoint to resume from.
        #expect(entry.record.itemId == nil)
    }

    @Test
    func signOutDropsEveryJobAndItsRecord() async {
        let cards = FakeCardGenerating()
        cards.confirmFailures = 1
        let journal = InMemoryCaptureJobJournal()
        let queue = self.queue(cards: cards, journal: journal)

        await queue.enqueue(imageId: "img-1", payload: AtlasFixtures.payload(), thumbnail: nil).value
        queue.reset()

        // A journalled job survives app kills, so leaving one behind would resume
        // the previous account's capture under the next account's session.
        #expect(queue.jobs.isEmpty)
        #expect(journal.entries.isEmpty)
    }

    @Test
    func inFlightCountIsTheSlotCapacityCannotSeeOnTheServer() async {
        let cards = FakeCardGenerating()
        cards.confirmFailures = 1
        let queue = self.queue(cards: cards)

        let running = queue.enqueue(imageId: "img-1", payload: AtlasFixtures.payload(), thumbnail: nil)
        // Committed, not yet counted by the server's usage snapshot.
        #expect(queue.inFlightCount == 1)
        await running.value
        // A failed job holds no slot: nothing was confirmed.
        #expect(queue.inFlightCount == 0)
    }
}
