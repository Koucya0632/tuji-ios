// Per-word mastery cache, mirroring WordsStore's shape. Loads the user's
// whole mastery map once from GET /api/users/mastery and exposes a fast
// id → score lookup so the 圖鑑 grid and word detail can derive their
// MasteryLevel badge without per-word fetches.
//
// Decay is applied server-side at read, so the scores here are "as of the
// last load". After a study session CompleteView calls invalidate() + reload()
// so the grid/detail reflect the just-earned changes. Guests / load failures
// leave the map empty → every word renders as 未學.

import Foundation
import Observation
import OSLog

@MainActor
@Observable
final class MasteryStore {
    static let shared = MasteryStore()

    private(set) var byId: [String: Int] = [:]
    /// wordId → soonest next-review date, for the 圖鑑 countdown. Only words
    /// with a scheduled card appear here.
    private(set) var nextReviewById: [String: Date] = [:]
    private(set) var loading: Bool = false
    private(set) var lastError: Error?

    /// True once the first load attempt finishes (success *or* failure). Used
    /// to avoid re-fetching for users who legitimately have an empty map.
    private(set) var loaded: Bool = false

    private let repository: ProgressRepository
    private let log = Logger(subsystem: "app.tuji.ios", category: "mastery-store")

    private init(repository: ProgressRepository = LiveProgressRepository.shared) {
        self.repository = repository
    }

    /// Score for a word, or nil if the user has never studied it (→ 未學).
    func score(for wordId: String) -> Int? {
        self.byId[wordId]
    }

    /// Next-due review date for a word, or nil if it has no scheduled card.
    func nextReviewDate(for wordId: String) -> Date? {
        self.nextReviewById[wordId]
    }

    /// Fetch once. Returns immediately after the first attempt; use reload()
    /// to force a refresh.
    ///
    /// No TTL, deliberately — and this is the one place in the accumulation
    /// readout where the staleness policy differs. `ProgressStore` and
    /// `StudyStatsStore` both use `loadIfStale(ttl: 30)` because their numbers
    /// move on their own: `due` crosses midnight, the streak turns over, the
    /// heatmap gains a day. Mastery does not. Decay is applied server-side at
    /// read, but a score only *changes* when this user answers something, and
    /// every path that answers something already invalidates this store through
    /// `SessionRefresh`. A 30-second TTL here would re-fetch the whole map on
    /// every tab swap to buy a number that cannot have moved.
    ///
    /// The cost of the choice: a session on another device does not show up
    /// here until this one is relaunched or pull-to-refreshed. 首頁 has that
    /// pull; 我 does not.
    func loadIfNeeded() async {
        guard !self.loaded else { return }
        await self.reload()
    }

    func reload() async {
        self.loading = true
        self.lastError = nil
        defer {
            self.loading = false
            self.loaded = true
        }
        do {
            let resp = try await self.repository.loadMastery()
            self.byId = Dictionary(
                resp.items.map { ($0.wordId, $0.mastery) },
                uniquingKeysWith: { _, last in last }
            )
            var schedule: [String: Date] = [:]
            for item in resp.items {
                if let iso = item.nextReviewAt, let date = ReviewSchedule.parseISO(iso) {
                    schedule[item.wordId] = date
                }
            }
            self.nextReviewById = schedule
            self.log.info("loaded \(resp.items.count, privacy: .public) mastery rows")
        } catch {
            self.lastError = error
            self.log.error("mastery load failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Mark the next loadIfNeeded as a guaranteed miss. Call after a study
    /// session so the grid/detail re-fetch fresh scores.
    func invalidate() {
        self.loaded = false
    }
}

struct MasteryEntry: Decodable, Hashable {
    let wordId: String
    let mastery: Int
    /// ISO8601 string (not Date): the global .iso8601 decoder rejects the
    /// fractional seconds the server emits. Parsed via ReviewSchedule.parseISO.
    let nextReviewAt: String?
}

struct MasteryListResponse: Decodable {
    let items: [MasteryEntry]
}
