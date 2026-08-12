// 生成佇列 — the durable tail of the 自製圖鑑 capture flow. Once the user confirms
// a name in AtlasCaptureView, confirm → createCards → enrich → one reconciling
// read runs here instead of blocking the sheet. The 卡片 grid renders these jobs
// as 生成中 tiles at the head of its own grid.
//
// Jobs are owned by this @MainActor singleton, so they keep running after the
// capture cover is dismissed. Completion refreshes counters in place via
// reload() — never invalidate(), which would clear WordsStore.loaded and bounce
// the whole app back to Splash (see memory: rootview-invalidate-splash-bounce).
//
// Weak-network resilience: jobs are journalled, so an app kill mid-flight does
// not lose committed work — on launch the queue restores and resumes them.
// confirm is a plain INSERT server-side (not idempotent), so once it succeeds
// the itemId is checkpointed; a resumed run then skips confirm and continues
// from createCards (which IS idempotent).
//
// Everything the queue reaches now arrives through an init parameter. It used to
// reach `AtlasStore.shared` at four call sites and `FileManager` at five, behind
// a `private init` — so the checkpoint rule above, the only thing standing
// between a resumed run and a duplicate 自製圖鑑 card, was verified by nothing.
// ADR-0001's amendment already said it: a seam defaulted to `.shared` that no
// test can construct is not a seam. Production still goes through `.shared`.

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

        fileprivate let payload: AtlasConfirmPayload
        /// Set once confirm succeeds, so a resumed run never re-confirms.
        fileprivate var itemId: String?

        fileprivate init(record: CaptureJobRecord, thumbnail: UIImage?) {
            self.id = record.id
            self.imageId = record.imageId
            self.lemma = record.lemma
            self.thumbnail = thumbnail
            self.payload = record.payload
            self.itemId = record.itemId
            self.progress = .generating(Self.startingFraction(resuming: record.itemId != nil))
        }

        fileprivate var record: CaptureJobRecord {
            CaptureJobRecord(
                id: self.id,
                imageId: self.imageId,
                payload: self.payload,
                lemma: self.lemma,
                itemId: self.itemId
            )
        }

        /// A job with a checkpoint has already confirmed. Restarting it from the
        /// top would re-announce work the server has finished — the bar would
        /// walk back to 15% for a card that already exists.
        fileprivate static func startingFraction(resuming: Bool) -> Double {
            resuming ? 0.5 : 0.15
        }
    }

    private(set) var jobs: [Job] = []

    /// Captures committed but not yet counted by the server's usage snapshot.
    /// `AtlasCapacityReadout` folds this in — a queued job has already claimed a
    /// 自製圖鑑 slot, and the gate that ignored them let a second capture through
    /// at capacity − 1 only to die as a retry-forever tile.
    var inFlightCount: Int {
        self.jobs.count(where: { !$0.progress.isFailed && $0.progress != .ready })
    }

    private let log = Logger(subsystem: "app.tuji.ios", category: "atlas-capture-queue")
    /// Signpost the confirm→cards→enrich tail so the pipeline is measurable in
    /// Instruments (per-stage timing + failure rate); the production funnel is
    /// derived server-side from the atlas tables.
    private let signposter = OSSignposter(subsystem: "app.tuji.ios", category: "atlas-capture")

    private let cards: AtlasCardGenerating
    private let journal: CaptureJobJournal
    /// What a finished capture refreshes is not this queue's decision — it
    /// belongs to `AtlasMutationRefresh`, shared with the manage screen's delete.
    private let mutations: AtlasMutationRefreshing
    /// How long a finished tile stays on the grid saying 已加入圖鑑 before it is
    /// replaced by the real card. Configurable so a test is not a four-second wait.
    private let doneLinger: Duration
    private let celebrate: @MainActor () -> Void

    private var running: [UUID: Task<Void, Never>] = [:]

    init(
        cards: AtlasCardGenerating = AtlasStore.shared,
        journal: CaptureJobJournal = FileCaptureJobJournal(),
        mutations: AtlasMutationRefreshing = LiveAtlasMutationRefresher(),
        doneLinger: Duration = .seconds(4),
        celebrate: @escaping @MainActor () -> Void = {
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        }
    ) {
        self.cards = cards
        self.journal = journal
        self.mutations = mutations
        self.doneLinger = doneLinger
        self.celebrate = celebrate
        self.restore()
    }

    /// The returned task is the job. Production ignores it — the queue owns the
    /// lifetime, which is the whole point of handing work here — but a caller
    /// that wants to observe completion can, and a test that cannot wait for a
    /// pipeline can only assert on it by polling, which is how CI flakes start.
    @discardableResult
    func enqueue(imageId: String, payload: AtlasConfirmPayload, thumbnail: UIImage?) -> Task<Void, Never> {
        let record = CaptureJobRecord(
            id: UUID(),
            imageId: imageId,
            payload: payload,
            lemma: payload.lemma,
            itemId: nil
        )
        self.jobs.append(Job(record: record, thumbnail: thumbnail))
        self.journal.save(record, thumbnail: thumbnail?.jpegData(compressionQuality: 0.6))
        return self.start(record.id)
    }

    /// Only a transient failure can be retried. A capture that died at capacity
    /// would fail the same way every time, so the tile does not offer it.
    @discardableResult
    func retry(_ id: UUID) -> Task<Void, Never>? {
        guard let job = self.jobs.first(where: { $0.id == id }), job.progress.canRetry else { return nil }
        self.update(id) {
            $0.progress = .generating(Job.startingFraction(resuming: $0.itemId != nil))
        }
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
            let itemId: String
            if let existing = job.itemId {
                // confirm already succeeded in a prior run — reuse the item so a
                // resume never creates a duplicate.
                self.signposter.emitEvent("resume", id: signpostID)
                itemId = existing
            } else {
                let item = try await self.cards.confirm(imageId: job.imageId, payload: job.payload)
                itemId = item.id
                self.update(id) { $0.itemId = item.id }
                self.checkpoint(id) // before the (idempotent) tail
                self.signposter.emitEvent("confirmed", id: signpostID)
            }
            self.update(id) { $0.progress = .generating(0.5) }
            try await self.cards.generateCards(forItem: itemId)
            self.signposter.emitEvent("carded", id: signpostID)
            self.update(id) { $0.progress = .enriching(0.7) }
            try? await self.cards.enrich(itemId: itemId)
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
            // Keep the journalled record so the job survives an app kill and can
            // be retried (from the itemId checkpoint if confirm already ran).
        }
    }

    private func update(_ id: UUID, _ mutate: (inout Job) -> Void) {
        guard let idx = self.jobs.firstIndex(where: { $0.id == id }) else { return }
        mutate(&self.jobs[idx])
    }

    /// Re-journal a job whose record changed — in practice, only ever to write
    /// the itemId checkpoint. The thumbnail is already on disk from `enqueue`.
    private func checkpoint(_ id: UUID) {
        guard let job = self.jobs.first(where: { $0.id == id }) else { return }
        self.journal.save(job.record, thumbnail: nil)
    }

    /// Reload jobs left over from a previous session and resume them. confirm is
    /// skipped when an itemId checkpoint exists, so createCards (idempotent) is
    /// the worst that can repeat.
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
