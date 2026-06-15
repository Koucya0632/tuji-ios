// Shared cache of /api/study/stats for the two screens that consume it:
// Today (hero due tile) and StudyLanding (new / review chips + backlog
// warning). Without sharing, jumping between Today and Study within a
// few seconds hits the endpoint twice and runs the five-count SQL
// fan-out twice.
//
// Server already caches `studyStats(userId, categories)` with a 30s
// revalidate + `stats:<uid>` tag, busted on /api/study/answer. This
// store mirrors that 30s window on the client, with `invalidate()`
// called after a session ends so the next read sees fresh counts.
//
// iOS currently calls stats with no category filter (global counts),
// so a single key is enough. If a category-filtered call ever lands,
// switch to a dict keyed by sorted-category-csv.

import Foundation
import Observation
import OSLog

@MainActor
@Observable
final class StudyStatsStore {
    static let shared = StudyStatsStore()

    private(set) var stats: StudyStats?
    private(set) var loading: Bool = false
    private(set) var lastError: Error?

    private var lastFetch: Date?
    private let log = Logger(subsystem: "app.tuji.ios", category: "study-stats-store")

    private init() {}

    func loadIfStale(ttl: TimeInterval = 30) async {
        if let last = lastFetch, Date().timeIntervalSince(last) < ttl, stats != nil {
            return
        }
        await reload()
    }

    func reload() async {
        loading = true
        lastError = nil
        defer { loading = false }
        do {
            let resp: StudyStatsResponse = try await APIClient.shared.get(.studyStats)
            stats = resp.stats
            lastFetch = Date()
        } catch {
            lastError = error
            log.error("study stats load failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    func invalidate() {
        lastFetch = nil
    }
}
