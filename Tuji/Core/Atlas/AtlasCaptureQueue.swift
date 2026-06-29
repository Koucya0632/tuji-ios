// Background queue for the 自制圖鑑 capture flow. Once the user confirms a name
// in AtlasCaptureView, the heavy tail — confirm → createCards → one reconciling
// sync — runs here instead of blocking the sheet. The 圖鑑 page renders these
// jobs as "製作中" placeholder cards (AtlasCaptureProgressStrip).
//
// Jobs are owned by this @MainActor singleton, so they keep running after the
// capture cover is dismissed. Completion refreshes counters in place via
// reload() — never invalidate(), which would clear WordsStore.loaded and bounce
// the whole app back to Splash (see memory: rootview-invalidate-splash-bounce).

import Observation
import OSLog
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
        let id = UUID()
        let imageId: String
        let payload: AtlasConfirmPayload
        let thumbnail: UIImage?
        let lemma: String
        var stage: Stage
        var progress: Double
    }

    private(set) var jobs: [Job] = []

    private let log = Logger(subsystem: "app.tuji.ios", category: "atlas-capture-queue")

    private init() {}

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
    }

    private func run(_ id: UUID) async {
        guard let job = self.jobs.first(where: { $0.id == id }) else { return }
        do {
            let item = try await AtlasStore.shared.confirm(imageId: job.imageId, payload: job.payload)
            self.update(id) { $0.stage = .creating; $0.progress = 0.5 }
            _ = try await AtlasStore.shared.createCards(itemId: item.id)
            // Enrich (definition / synonyms / forms / etymology) so the card's
            // detail page matches a dictionary word. Best-effort — a failure
            // doesn't fail the card; the detail endpoint lazily enriches on open.
            self.update(id) { $0.stage = .enriching; $0.progress = 0.7 }
            try? await AtlasStore.shared.enrich(itemId: item.id)
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
            try? await Task.sleep(for: .seconds(4))
            self.remove(id)
        } catch {
            self.log.error("capture job failed: \(error.localizedDescription, privacy: .public)")
            self.update(id) { $0.stage = .failed }
        }
    }

    private func update(_ id: UUID, _ mutate: (inout Job) -> Void) {
        guard let idx = self.jobs.firstIndex(where: { $0.id == id }) else { return }
        mutate(&self.jobs[idx])
    }
}
