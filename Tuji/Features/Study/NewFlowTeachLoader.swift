// Prefetches the full Word detail (definition + example sentences) for a
// NewFlow session so RecognizeView can teach before it asks. Custom words
// already embed their detail in the words store (no network); public words
// fetch /api/words/{id} one by one in queue order, so the first card's
// detail lands first and later cards are long warmed by the time their
// recognize step surfaces. A miss just renders the plain recognize card —
// no spinner, no layout jump, never blocks the lesson.

import Foundation
import OSLog
import Observation

@MainActor
@Observable
final class NewFlowTeachLoader {
    /// word.id → full detail, filled in as fetches land.
    private(set) var details: [String: Word] = [:]

    private let log = Logger(subsystem: "app.tuji.ios", category: "new-flow-teach")

    func preload(
        queue: [StudyQueueItem],
        words: WordsStore,
        catalog: CatalogRepository = LiveCatalogRepository.shared
    ) async {
        var pendingIds: [String] = []
        for item in queue {
            let id = item.word.id
            guard self.details[id] == nil else { continue }
            if id.hasPrefix("atlas:") {
                // 自制圖鑑 words carry their enriched detail in the store.
                if let detail = words.find(id: id)?.detail {
                    self.details[id] = detail
                }
            } else {
                pendingIds.append(id)
            }
        }

        // Sequential on purpose: queue order matches teaching order, each
        // fetch is one small cached payload, and a session is ~10 words —
        // fan-out would buy little and costs Sendable gymnastics.
        let settings = SettingsStore.shared.current
        for id in pendingIds {
            guard !Task.isCancelled else { return }
            do {
                self.details[id] = try await catalog.word(
                    id: id,
                    lang: settings.uiLang,
                    learning: settings.learningDirection.rawValue
                )
            } catch {
                self.log.info("teach detail miss for \(id, privacy: .public)")
            }
        }
    }
}
