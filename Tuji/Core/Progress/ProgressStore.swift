// Shared streak + heatmap cache for the four screens that read
// /api/users/progress (Today, Progress tab, Me, post-answer Complete).
// Without this, swapping tabs within ~30s re-hits the endpoint each
// time and the server runs the gaps-and-islands streak SQL on every
// hit. The store keeps a single fetched copy and exposes `loadIfStale`
// to ignore reads within `ttl`.
//
// After /api/study/answer the server revalidates its cache; `invalidate()`
// here forces the next `loadIfStale` to round-trip so the new streak
// shows up immediately on CompleteView.

import Foundation
import Observation
import OSLog

@MainActor
@Observable
final class ProgressStore {
    static let shared = ProgressStore()

    private(set) var streak: StudyStreak?
    private(set) var heatmap: [HeatmapCell] = []
    private(set) var categoryProgress: [CategoryProgress] = []
    private(set) var loading: Bool = false
    private(set) var lastError: Error?

    private var lastFetch: Date?
    private let log = Logger(subsystem: "app.tuji.ios", category: "progress-store")

    private init() {}

    /// Refresh from server if no fetch yet, or the last one is older than `ttl`.
    /// Returns immediately on a hit. Safe to call from view `.task`.
    func loadIfStale(ttl: TimeInterval = 30) async {
        if let last = lastFetch, Date().timeIntervalSince(last) < ttl, streak != nil {
            return
        }
        await reload()
    }

    func reload() async {
        loading = true
        lastError = nil
        defer { loading = false }
        do {
            let resp: ProgressResponse = try await APIClient.shared.get(.usersProgress)
            streak = resp.streak
            heatmap = resp.heatmap ?? []
            categoryProgress = resp.categories ?? []
            lastFetch = Date()
        } catch {
            lastError = error
            log.error("progress load failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Mark the next `loadIfStale` as a guaranteed miss. Call after any write
    /// that affects streak / heatmap (study/answer success, clearProgress).
    func invalidate() {
        lastFetch = nil
    }

    // MARK: - Category-scoped totals

    /// Words seen at least once across the given categories. An empty filter
    /// means "all categories" — matches the backend's `category` param, where
    /// empty = no filter. Used by Today's hero + the Progress completion card.
    func seenCount(filter categories: [String]) -> Int {
        self.rows(filter: categories).reduce(0) { $0 + $1.seen }
    }

    /// Published-card total across the given categories. Empty filter = all.
    func totalCount(filter categories: [String]) -> Int {
        self.rows(filter: categories).reduce(0) { $0 + $1.total }
    }

    private func rows(filter categories: [String]) -> [CategoryProgress] {
        guard !categories.isEmpty else { return self.categoryProgress }
        let wanted = Set(categories)
        return self.categoryProgress.filter { wanted.contains($0.category) }
    }
}
