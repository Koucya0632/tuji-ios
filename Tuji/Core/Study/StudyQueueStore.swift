// Caches the study queue per mode so the common "open app → tap 復習 / 學新字"
// path skips the network round-trip. TodayView pre-fetches in the background
// while the user reads the home screen; StudyLauncherView consumes the warm
// queue via take(mode:), or falls back to a live fetch(mode:) on a miss.
//
// Centralises the param computation + word-id dedupe that used to live inline
// in StudyLauncherView so the prefetch and the direct fetch can't drift apart.
//
// /api/study/queue is a read-only GET, so prefetching has no server side
// effects — it just moves the same request earlier for users who do study.

import Foundation
import Observation
import OSLog

@MainActor
@Observable
final class StudyQueueStore {
    static let shared = StudyQueueStore()

    /// How long a prefetched queue stays usable. Short because the queue
    /// reflects SRS state; the signature (which folds in the live `due` count)
    /// already bypasses a stale entry — this just backstops it.
    private let ttl: TimeInterval = 90

    private struct Entry {
        let queue: [StudyQueueItem]
        let signature: String
        let fetchedAt: Date
    }

    private struct Params {
        let limit: Int
        let newCount: Int
        let categories: [String]
        let signature: String
    }

    private var entries: [StudyMode: Entry] = [:]
    private let repository: StudyRepository
    private let log = Logger(subsystem: "app.tuji.ios", category: "study-queue-store")

    private init(repository: StudyRepository = LiveStudyRepository.shared) {
        self.repository = repository
    }

    /// Read the warm queue for `mode` if it still matches the current params and
    /// hasn't expired, consuming it so a re-entry without a fresh prefetch falls
    /// back to a live fetch. nil on a miss.
    func take(mode: StudyMode) -> [StudyQueueItem]? {
        let params = self.params(for: mode)
        guard let entry = self.entries[mode],
              entry.signature == params.signature,
              Date().timeIntervalSince(entry.fetchedAt) < self.ttl
        else { return nil }
        self.entries[mode] = nil
        return entry.queue
    }

    /// Best-effort background warm. No-op when a fresh matching entry exists;
    /// swallows errors so a failed prefetch just leaves the launcher to fetch.
    func prefetch(mode: StudyMode) async {
        let params = self.params(for: mode)
        if let entry = self.entries[mode],
           entry.signature == params.signature,
           Date().timeIntervalSince(entry.fetchedAt) < self.ttl {
            return
        }
        do {
            let queue = try await self.fetch(mode: mode, params: params)
            self.entries[mode] = Entry(queue: queue, signature: params.signature, fetchedAt: Date())
        } catch {
            self.log
                .error("prefetch \(mode.asPath, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Live fetch + dedupe, used by the launcher on a cache miss.
    func fetch(mode: StudyMode) async throws -> [StudyQueueItem] {
        try await self.fetch(mode: mode, params: self.params(for: mode))
    }

    func invalidate() {
        self.entries.removeAll()
    }

    // MARK: - Internals

    private func fetch(mode: StudyMode, params: Params) async throws -> [StudyQueueItem] {
        let resp = try await self.repository.loadQueue(
            mode: mode,
            limit: params.limit,
            newCount: params.newCount,
            categories: params.categories
        )
        // A custom 自制圖鑑 item can carry more than one card (image_recall +
        // flashcard), but the unified flow studies a word once and the queue is
        // keyed by word.id (StudyQueueItem.id). Collapse to one item per word so
        // the same word can't surface twice in a session — keep the first, since
        // the server orders in-progress reviews ahead of new cards.
        var seenWordIds = Set<String>()
        return resp.queue.filter { seenWordIds.insert($0.word.id).inserted }
    }

    /// Mirrors the old StudyLauncherView.loadQueue() param logic. New cards are
    /// drawn from the user's selected themes; review spans every studied word so
    /// it sends no filter. The signature folds in everything that should bust a
    /// cached entry, including the live `due` count.
    private func params(for mode: StudyMode) -> Params {
        let due = StudyStatsStore.shared.stats?.due ?? 0
        let settings = SettingsStore.shared.current
        let limit: Int
        let newCount: Int
        let categories: [String]
        switch mode {
        case .new:
            let n = StudyQuotas.computeNewLimit(goal: settings.dailyGoal, due: due)
            limit = n
            newCount = n
            categories = settings.studyCategories
        case .review:
            limit = min(due, 30)
            newCount = 0
            categories = []
        }
        let signature = "\(mode.asPath)|\(limit)|\(newCount)|\(categories.sorted().joined(separator: ","))|due\(due)"
        return Params(limit: limit, newCount: newCount, categories: categories, signature: signature)
    }
}
