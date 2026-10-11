// 生成佇列 — the durable tail of a 拍照新增 capture. Once the user confirms a
// candidate in `CreditCaptureView`, confirm → createCards → wait for the server's
// 補充 → one reconciling read runs here instead of blocking the sheet. The 卡片
// grid renders these jobs as 生成中 tiles at the head of its own grid.
//
// Jobs are owned by this @MainActor singleton, so they keep running after the
// capture cover is dismissed. Completion refreshes counters in place via
// reload() — never invalidate(), which would clear WordsStore.loaded and bounce
// the whole app back to Splash (see memory: rootview-invalidate-splash-bounce).
//
// Weak-network resilience: jobs are journalled, so an app kill mid-flight does
// not lose committed work — on launch the queue restores and resumes them.
// **Every step is safe to repeat.** The confirm is bound to its operation
// server-side and answers a resend with the card it already made, and
// createCards is idempotent, so a resumed job simply runs again from the top.
// The pre-credit flow's confirm was a plain INSERT and needed an itemId
// checkpoint to survive a resume; that flow and its checkpoint are gone
// (docs/adr/0016).
//
// Everything the queue reaches arrives through an init parameter. ADR-0001's
// amendment: a seam defaulted to `.shared` that no test can construct is not a
// seam. Production still goes through `.shared`.

import OSLog
import Observation
import SwiftUI
import UIKit

@MainActor
@Observable
final class AtlasCaptureQueue {
    static let shared = AtlasCaptureQueue()

    struct Job: Identifiable {
        let id: UUID
        let imageId: String
        let lemma: String
        let thumbnail: UIImage?
        /// Where this capture sits, in the vocabulary both screens read.
        /// `CaptureProgress` replaced a queue-private `Stage` enum that only the
        /// grid tile understood.
        fileprivate(set) var progress: CaptureProgress

        /// What the user confirmed. The operation it names is what makes a
        /// resend safe.
        fileprivate let credit: CreditConfirmRequest

        fileprivate init(record: CaptureJobRecord, thumbnail: UIImage?) {
            self.id = record.id
            self.imageId = record.imageId
            self.lemma = record.lemma
            self.thumbnail = thumbnail
            self.credit = record.credit
            self.progress = .generating(Self.startingFraction)
        }

        fileprivate var record: CaptureJobRecord {
            CaptureJobRecord(id: self.id, imageId: self.imageId, lemma: self.lemma, credit: self.credit)
        }

        fileprivate static let startingFraction = 0.15
    }

    private(set) var jobs: [Job] = []

    private let log = Logger(subsystem: "app.tuji.ios", category: "atlas-capture-queue")
    /// Signpost the confirm→cards→enrich tail so the pipeline is measurable in
    /// Instruments (per-stage timing + failure rate); the production funnel is
    /// derived server-side from the atlas tables.
    private let signposter = OSSignposter(subsystem: "app.tuji.ios", category: "atlas-capture")

    private let cards: AtlasCardGenerating
    private let credits: CreditCardConfirming
    private let journal: CaptureJobJournal
    /// What a finished capture refreshes is not this queue's decision — it
    /// belongs to `AtlasMutationRefresh`, shared with the manage screen's delete.
    private let mutations: AtlasMutationRefreshing
    /// How long a finished tile stays on the grid saying 已加入圖鑑 before it is
    /// replaced by the real card. Configurable so a test is not a four-second wait.
    private let doneLinger: Duration
    /// How often a 罐頭點數 job asks whether the server's fill-in has landed.
    private let enrichmentPoll: Duration
    /// A fill-in that fails retries two minutes later. Past this the job
    /// finishes anyway — the card exists — and the fields arrive on a later reload.
    private let enrichmentDeadline: Duration
    private let celebrate: @MainActor () -> Void

    private var running: [UUID: Task<Void, Never>] = [:]

    init(
        cards: AtlasCardGenerating = AtlasStore.shared,
        credits: CreditCardConfirming = LiveCreditCardConfirming(),
        journal: CaptureJobJournal = FileCaptureJobJournal(),
        mutations: AtlasMutationRefreshing = LiveAtlasMutationRefresher(),
        doneLinger: Duration = .seconds(4),
        enrichmentPoll: Duration = .seconds(2),
        enrichmentDeadline: Duration = .seconds(150),
        celebrate: @escaping @MainActor () -> Void = {
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        }
    ) {
        self.cards = cards
        self.credits = credits
        self.journal = journal
        self.mutations = mutations
        self.doneLinger = doneLinger
        self.enrichmentPoll = enrichmentPoll
        self.enrichmentDeadline = enrichmentDeadline
        self.celebrate = celebrate
        self.restore()
    }

    /// A result the user confirmed.
    ///
    /// The returned task is the job. Production ignores it — the queue owns the
    /// lifetime, which is the whole point of handing work here — but a caller
    /// that wants to observe completion can, and a test that cannot wait for a
    /// pipeline can only assert on it by polling, which is how CI flakes start.
    @discardableResult
    func enqueue(credit: CreditConfirmRequest, imageId: String, thumbnail: UIImage?) -> Task<Void, Never> {
        let record = CaptureJobRecord(id: UUID(), imageId: imageId, lemma: credit.lemma, credit: credit)
        return self.add(record, thumbnail: thumbnail)
    }

    /// Operations whose confirm this queue owns. 拍照新增 must not reopen one as
    /// a result still waiting to be picked.
    var creditOperationIds: Set<String> {
        Set(self.jobs.map(\.credit.operationId))
    }

    private func add(_ record: CaptureJobRecord, thumbnail: UIImage?) -> Task<Void, Never> {
        self.jobs.append(Job(record: record, thumbnail: thumbnail))
        self.journal.save(record, thumbnail: thumbnail?.jpegData(compressionQuality: 0.6))
        return self.start(record.id)
    }

    /// Only a transient failure can be retried. A capture that died at capacity
    /// would fail the same way every time, so the tile does not offer it.
    @discardableResult
    func retry(_ id: UUID) -> Task<Void, Never>? {
        guard let job = self.jobs.first(where: { $0.id == id }), job.progress.canRetry else { return nil }
        self.update(id) { $0.progress = .generating(Job.startingFraction) }
        return self.start(id)
    }

    func remove(_ id: UUID) {
        self.jobs.removeAll { $0.id == id }
        self.journal.remove(id)
    }

    /// Drop every job, in memory and on disk. Called on sign-out — a journalled
    /// job survives app kills and would otherwise resume under the next
    /// account's session and surface the previous account's capture there.
    /// In-flight requests fail with 401 once the session is gone; their
    /// `update` calls no-op after the job is removed.
    func reset() {
        for task in self.running.values {
            task.cancel()
        }
        self.running = [:]
        self.jobs = []
        self.journal.removeAll()
    }

    /// Await every job currently in flight.
    ///
    /// This is the observability the module never had: `enqueue` returns before
    /// the work it commits, which is correct for the sheet and impossible for a
    /// test. Nothing in production calls it — sign-out deliberately drops
    /// in-flight jobs rather than waiting for them.
    func settle() async {
        while let task = self.running.values.first {
            await task.value
        }
    }

    private func start(_ id: UUID) -> Task<Void, Never> {
        let task = Task { [weak self] in
            await self?.run(id)
            self?.running[id] = nil
        }
        self.running[id] = task
        return task
    }

    private func run(_ id: UUID) async {
        guard let job = self.jobs.first(where: { $0.id == id }) else { return }
        let signpostID = self.signposter.makeSignpostID()
        let interval = self.signposter.beginInterval("capture-job", id: signpostID)
        defer { self.signposter.endInterval("capture-job", interval) }
        do {
            // Safe to resend on resume: the server returns the card it bound.
            let confirmed = try await self.credits.confirm(job.credit)
            self.signposter.emitEvent("confirmed", id: signpostID)
            self.update(id) { $0.progress = .generating(0.5) }
            try await self.cards.generateCards(forItem: confirmed.itemId)
            self.signposter.emitEvent("carded", id: signpostID)
            self.update(id) { $0.progress = .enriching(0.7) }
            await self.awaitFulfillment(job.credit.operationId, from: confirmed.fulfillment)
            guard !Task.isCancelled else { return }
            self.update(id) { $0.progress = .enriching(0.9) }
            // One reconciling read for the atlas list, then the shared policy for
            // everything else a finished capture touches (AtlasMutationRefresh).
            await self.cards.reconcile()
            await self.mutations.refresh(after: .captureCompleted)
            self.update(id) { $0.progress = .ready }
            self.celebrate()
            self.journal.remove(id) // done — drop the record now
            try? await Task.sleep(for: self.doneLinger)
            self.remove(id)
        } catch {
            self.signposter.emitEvent("failed", id: signpostID)
            self.log.error("capture job failed: \(error.localizedDescription, privacy: .public)")
            self.update(id) { $0.progress = .failed(CaptureFailure(error)) }
            // Keep the journalled record so the job survives an app kill and
            // can be retried.
        }
    }

    /// Waits out the server's fill-in so the finished tile hands over a card
    /// that already has its reading and definitions. A poll that fails is just
    /// asked again; the deadline is the only way out besides the fill-in ending.
    private func awaitFulfillment(_ operationId: String, from state: CreditOperation.Fulfillment) async {
        guard state.isOpen else { return }
        let deadline = ContinuousClock.now + self.enrichmentDeadline
        while ContinuousClock.now < deadline {
            do { try await Task.sleep(for: self.enrichmentPoll) } catch { return }
            if let state = try? await self.credits.fulfillment(operationId: operationId), !state.isOpen {
                return
            }
        }
        self.log.info("credit fill-in still open at the deadline; finishing the job anyway")
    }

    private func update(_ id: UUID, _ mutate: (inout Job) -> Void) {
        guard let idx = self.jobs.firstIndex(where: { $0.id == id }) else { return }
        mutate(&self.jobs[idx])
    }

    /// Reload jobs left over from a previous session and run them again.
    private func restore() {
        for entry in self.journal.restore() {
            let job = Job(
                record: entry.record,
                thumbnail: entry.thumbnail.flatMap(UIImage.init(data:))
            )
            self.jobs.append(job)
            _ = self.start(job.id)
        }
    }
}
