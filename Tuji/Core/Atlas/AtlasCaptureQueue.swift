// Background queue for the 自制圖鑑 capture flow. Once the user confirms a name
// in AtlasCaptureView, the heavy tail — confirm → createCards → enrich → one
// reconciling sync — runs here instead of blocking the sheet. The 圖鑑 page
// renders these jobs as "製作中" placeholder cards (AtlasCaptureProgressStrip).
//
// Jobs are owned by this @MainActor singleton, so they keep running after the
// capture cover is dismissed. Completion refreshes counters in place via
// reload() — never invalidate(), which would clear WordsStore.loaded and bounce
// the whole app back to Splash (see memory: rootview-invalidate-splash-bounce).
//
// Weak-network resilience (Phase 5): jobs are persisted to Application Support,
// so an app kill mid-flight doesn't lose committed work — on launch the queue
// restores and resumes them. confirm is a plain INSERT server-side (not
// idempotent), so once it succeeds we checkpoint the itemId; a resumed run then
// skips confirm and continues from createCards (which IS idempotent).

import OSLog
import Observation
import SwiftUI
import UIKit

@MainActor
@Observable
final class AtlasCaptureQueue {
    static let shared = AtlasCaptureQueue()

    enum Stage {
        case confirming
        case creating
        case enriching
        case done
        case failed
    }

    struct Job: Identifiable {
        let id: UUID
        let imageId: String
        let payload: AtlasConfirmPayload
        let thumbnail: UIImage?
        let lemma: String
        var stage: Stage
        var progress: Double
        /// Set once confirm succeeds, so a resumed run skips re-confirming (which
        /// would create a duplicate item — confirm is a plain INSERT server-side).
        var itemId: String?

        init(
            id: UUID = UUID(),
            imageId: String,
            payload: AtlasConfirmPayload,
            thumbnail: UIImage?,
            lemma: String,
            stage: Stage,
            progress: Double,
            itemId: String? = nil
        ) {
            self.id = id
            self.imageId = imageId
            self.payload = payload
            self.thumbnail = thumbnail
            self.lemma = lemma
            self.stage = stage
            self.progress = progress
            self.itemId = itemId
        }
    }

    private(set) var jobs: [Job] = []

    private let log = Logger(subsystem: "app.tuji.ios", category: "atlas-capture-queue")
    // Signpost the confirm→cards→enrich tail so the pipeline is measurable in
    // Instruments (per-stage timing + failure rate); the production funnel is
    // derived server-side from the atlas tables.
    private let signposter = OSSignposter(subsystem: "app.tuji.ios", category: "atlas-capture")

    /// On-disk home for in-flight jobs. Application Support survives app kills
    /// and (unlike Caches) is not purged under storage pressure.
    private let store: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("AtlasCaptureQueue", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    private init() {
        self.restore()
    }

    func enqueue(imageId: String, payload: AtlasConfirmPayload, thumbnail: UIImage?) {
        let job = Job(
            imageId: imageId,
            payload: payload,
            thumbnail: thumbnail,
            lemma: payload.lemma,
            stage: .confirming,
            progress: 0.15
        )
        self.jobs.append(job)
        self.persist(job)
        let id = job.id
        Task { await self.run(id) }
    }

    func retry(_ id: UUID) {
        guard let job = self.jobs.first(where: { $0.id == id }), job.stage == .failed else { return }
        self.update(id) { $0.stage = .confirming; $0.progress = 0.15 }
        Task { await self.run(id) }
    }

    func remove(_ id: UUID) {
        self.jobs.removeAll { $0.id == id }
        self.deletePersisted(id)
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
                let item = try await AtlasStore.shared.confirm(imageId: job.imageId, payload: job.payload)
                itemId = item.id
                self.update(id) { $0.itemId = item.id }
                self.persistCurrent(id) // checkpoint before the (idempotent) tail
                self.signposter.emitEvent("confirmed", id: signpostID)
            }
            self.update(id) { $0.stage = .creating; $0.progress = 0.5 }
            _ = try await AtlasStore.shared.createCards(itemId: itemId)
            self.signposter.emitEvent("carded", id: signpostID)
            // Enrich (definition / synonyms / forms / etymology) so the card's
            // detail page matches a dictionary word. Best-effort — a failure
            // doesn't fail the card; the detail endpoint lazily enriches on open.
            self.update(id) { $0.stage = .enriching; $0.progress = 0.7 }
            try? await AtlasStore.shared.enrich(itemId: itemId)
            self.update(id) { $0.progress = 0.9 }
            // One reconciling sync for the atlas list, plus in-place store
            // refresh. reload() only — invalidate() would bounce to Splash.
            // WordsStore matters: atlas items surface in the 圖鑑 grid as custom
            // words (/api/users/custom-words → id "atlas:…"), so reloading it is
            // what makes the new card appear there.
            await AtlasStore.shared.sync(since: nil)
            async let words: Void = WordsStore.shared.reload()
            async let progress: Void = ProgressStore.shared.reload()
            async let stats: Void = StudyStatsStore.shared.reload()
            _ = await (words, progress, stats)
            self.update(id) { $0.stage = .done; $0.progress = 1 }
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            self.deletePersisted(id) // done — drop the on-disk record now
            try? await Task.sleep(for: .seconds(4))
            self.remove(id)
        } catch {
            self.signposter.emitEvent("failed", id: signpostID)
            self.log.error("capture job failed: \(error.localizedDescription, privacy: .public)")
            self.update(id) { $0.stage = .failed }
            // Keep the persisted record so the job survives an app kill and can
            // be retried (from the itemId checkpoint if confirm already ran).
        }
    }

    private func update(_ id: UUID, _ mutate: (inout Job) -> Void) {
        guard let idx = self.jobs.firstIndex(where: { $0.id == id }) else { return }
        mutate(&self.jobs[idx])
    }

    // MARK: - Persistence

    private struct PersistedJob: Codable {
        let id: UUID
        let imageId: String
        let payload: AtlasConfirmPayload
        let lemma: String
        var itemId: String?
    }

    private func persist(_ job: Job) {
        let record = PersistedJob(
            id: job.id,
            imageId: job.imageId,
            payload: job.payload,
            lemma: job.lemma,
            itemId: job.itemId
        )
        if let data = try? JSONEncoder().encode(record) {
            try? data.write(to: self.jsonURL(job.id))
        }
        if let thumb = job.thumbnail, let jpg = thumb.jpegData(compressionQuality: 0.6) {
            try? jpg.write(to: self.thumbURL(job.id))
        }
    }

    private func persistCurrent(_ id: UUID) {
        guard let job = self.jobs.first(where: { $0.id == id }) else { return }
        self.persist(job)
    }

    private func deletePersisted(_ id: UUID) {
        try? FileManager.default.removeItem(at: self.jsonURL(id))
        try? FileManager.default.removeItem(at: self.thumbURL(id))
    }

    private func jsonURL(_ id: UUID) -> URL {
        self.store.appendingPathComponent("\(id.uuidString).json")
    }

    private func thumbURL(_ id: UUID) -> URL {
        self.store.appendingPathComponent("\(id.uuidString).jpg")
    }

    /// Reload jobs left over from a previous session and resume them. confirm is
    /// skipped when an itemId checkpoint exists, so createCards (idempotent) is
    /// the worst that can repeat.
    private func restore() {
        guard
            let files = try? FileManager.default.contentsOfDirectory(
                at: self.store,
                includingPropertiesForKeys: nil
            )
        else { return }
        for file in files where file.pathExtension == "json" {
            guard
                let data = try? Data(contentsOf: file),
                let record = try? JSONDecoder().decode(PersistedJob.self, from: data)
            else { continue }
            let job = Job(
                id: record.id,
                imageId: record.imageId,
                payload: record.payload,
                thumbnail: UIImage(contentsOfFile: self.thumbURL(record.id).path),
                lemma: record.lemma,
                stage: .confirming,
                progress: 0.15,
                itemId: record.itemId
            )
            self.jobs.append(job)
            let id = job.id
            Task { await self.run(id) }
        }
    }
}
