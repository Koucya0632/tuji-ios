// Pins the staleness policy CONTEXT.md calls load-bearing: ProgressStore and
// StudyStatsStore use a 30s TTL because their numbers move on their own (`due`
// crosses midnight, the streak turns over), while MasteryStore uses a once-flag
// with no TTL because a score only changes when *this* user answers something.
//
// None of it was assertable. All three stores took `repository:` defaulted to
// `.shared` and then sealed it with `private init`, so no test could construct
// one — and the correlation was exact: the four stores with an internal init
// have test suites, these three had none. ADR-0001's own 2026-08-03 amendment
// states the rule ("a seam defaulted to `.shared` that no test can construct is
// not a seam"); it had been applied to AtlasStore and nothing else.

import Foundation
import Testing
@testable import Tuji

@MainActor
struct AccumulationStoreStalenessTests {
    // MARK: - ProgressStore

    @Test
    func progressLoadsOnceThenAnswersFromCacheWithinTheTTL() async {
        let repo = SpyProgressRepository()
        let store = ProgressStore(repository: repo)

        await store.loadIfStale()
        await store.loadIfStale()

        #expect(repo.progressLoads == 1)
        #expect(store.streak?.current == 3)
    }

    @Test
    func progressRefetchesOnceTheTTLHasPassed() async {
        let repo = SpyProgressRepository()
        let store = ProgressStore(repository: repo)

        await store.loadIfStale()
        // A zero TTL is "anything already fetched is stale" — the same branch a
        // midnight rollover takes, without waiting 30s for it.
        await store.loadIfStale(ttl: 0)

        #expect(repo.progressLoads == 2)
    }

    @Test
    func invalidateMakesTheNextLoadAGuaranteedMiss() async {
        let repo = SpyProgressRepository()
        let store = ProgressStore(repository: repo)

        await store.loadIfStale()
        store.invalidate()
        await store.loadIfStale()

        #expect(repo.progressLoads == 2)
    }

    /// A failed load must not be cached as fresh, or a transient error would
    /// stick for the whole TTL.
    @Test
    func aFailedProgressLoadIsNotTreatedAsFresh() async {
        let repo = SpyProgressRepository()
        repo.failing = true
        let store = ProgressStore(repository: repo)

        await store.loadIfStale()
        await store.loadIfStale()

        #expect(repo.progressLoads == 2)
        #expect(store.lastError != nil)
        #expect(store.streak == nil)
    }

    // MARK: - Memoised selection queries

    /// 首頁 reads these through `TodayDecisions`, a *computed* property re-read
    /// about a dozen times in one `body` evaluation; 我 · 進度 hand-writes the
    /// same two numbers. Each read used to allocate a `Set` and walk every row.
    /// The memo must not change the answers, and must not outlive a reload.
    @Test
    func filteredProgressCountsAreMemoisedWithoutChangingTheAnswer() async throws {
        let repo = SpyProgressRepository()
        repo.categories = try [
            CategoryProgressFixture.make(category: "food", seen: 3, total: 10),
            CategoryProgressFixture.make(category: "body", seen: 1, total: 5)
        ]
        let store = ProgressStore(repository: repo)
        await store.loadIfStale()

        #expect(store.seenCount(filter: ["food"]) == 3)
        #expect(store.seenCount(filter: ["food"]) == 3) // served from the memo
        #expect(store.totalCount(filter: ["food"]) == 10)
        #expect(store.seenCount(filter: ["food", "body"]) == 4)
        // An empty filter means "all categories", never a cached subset.
        #expect(store.totalCount(filter: []) == 15)
    }

    @Test
    func theFilteredRowMemoDoesNotSurviveAReload() async throws {
        let repo = SpyProgressRepository()
        repo.categories = try [CategoryProgressFixture.make(category: "food", seen: 3, total: 10)]
        let store = ProgressStore(repository: repo)
        await store.loadIfStale()
        #expect(store.seenCount(filter: ["food"]) == 3)

        repo.categories = try [CategoryProgressFixture.make(category: "food", seen: 9, total: 10)]
        store.invalidate()
        await store.loadIfStale()

        #expect(store.seenCount(filter: ["food"]) == 9)
    }

    // MARK: - MasteryStore

    /// No TTL by design: a score only moves when this user answers something,
    /// and every path that does invalidates through SessionRefresh.
    @Test
    func masteryLoadsOnceAndNeverExpires() async {
        let repo = SpyProgressRepository()
        let store = MasteryStore(repository: repo)

        await store.loadIfNeeded()
        await store.loadIfNeeded()

        #expect(repo.masteryLoads == 1)
        #expect(store.loaded)
    }

    /// The once-flag is set on *failure* too — a user with a legitimately empty
    /// map must not re-fetch forever — so invalidation is the only way back.
    @Test
    func masteryReloadsOnlyAfterInvalidation() async {
        let repo = SpyProgressRepository()
        let store = MasteryStore(repository: repo)

        await store.loadIfNeeded()
        store.invalidate()
        await store.loadIfNeeded()

        #expect(repo.masteryLoads == 2)
    }

    @Test
    func masteryExposesScoresById() async {
        let repo = SpyProgressRepository()
        let store = MasteryStore(repository: repo)

        await store.loadIfNeeded()

        #expect(store.score(for: "w-apple") == 42)
        #expect(store.score(for: "w-nothing") == nil)
    }

    // MARK: - StudyStatsStore

    @Test
    func statsLoadOnceThenAnswerFromCacheWithinTheTTL() async {
        let repo = SpyStudyRepository()
        let store = StudyStatsStore(repository: repo)

        await store.loadIfStale()
        await store.loadIfStale()

        #expect(repo.statsLoads == 1)
        #expect(store.stats?.due == 7)
    }

    @Test
    func statsRefetchAfterInvalidation() async {
        let repo = SpyStudyRepository()
        let store = StudyStatsStore(repository: repo)

        await store.loadIfStale()
        store.invalidate()
        await store.loadIfStale()

        #expect(repo.statsLoads == 2)
    }
}

@MainActor
private final class SpyProgressRepository: ProgressRepository {
    var failing = false
    var categories: [CategoryProgress] = []
    private(set) var progressLoads = 0
    private(set) var masteryLoads = 0

    struct Boom: Error {}
    struct NotImplemented: Error {}

    func loadProgress() async throws -> ProgressResponse {
        self.progressLoads += 1
        if self.failing { throw Boom() }
        return ProgressResponse(
            streak: StudyStreak(
                current: 3,
                longest: 9,
                totalDays: 12,
                todayCount: 1,
                lastStudyDate: nil
            ),
            heatmap: [],
            categories: self.categories
        )
    }

    func loadMastery() async throws -> MasteryListResponse {
        self.masteryLoads += 1
        if self.failing { throw Boom() }
        return try JSONDecoder.tuji.decode(
            MasteryListResponse.self,
            from: Data(#"{"items":[{"wordId":"w-apple","mastery":42,"nextReviewAt":null}]}"#.utf8)
        )
    }

    func clearProgress() async throws {
        throw NotImplemented()
    }

    func loadTopWords(type _: String, limit _: Int) async throws -> TopWordsResponse {
        throw NotImplemented()
    }

    func toggleFavorite(wordId _: String, isFavorite _: Bool) async {}
}

@MainActor
private final class SpyStudyRepository: StudyRepository {
    private(set) var statsLoads = 0

    struct NotImplemented: Error {}

    func loadStats() async throws -> StudyStatsResponse {
        self.statsLoads += 1
        return StudyStatsResponse(
            stats: StudyStats(total: 100, seen: 30, due: 7, new: 5, todayNew: 2)
        )
    }

    func loadQueue(
        mode _: StudyMode,
        limit _: Int,
        newCount _: Int,
        categories _: [String]
    ) async throws
        -> StudyQueueResponse
    {
        throw NotImplemented()
    }

    func submitAnswer(_: StudyAnswerPayload) async throws -> StudyAnswerResponse {
        throw NotImplemented()
    }

    func submitReport(_: StudyReportPayload) async throws {
        throw NotImplemented()
    }
}

/// `CategoryProgress` is `Decodable` only, so fixtures go through JSON.
enum CategoryProgressFixture {
    static func make(category: String, seen: Int, total: Int) throws -> CategoryProgress {
        try JSONDecoder.tuji.decode(
            CategoryProgress.self,
            from: Data(#"{"category":"\#(category)","seen":\#(seen),"total":\#(total)}"#.utf8)
        )
    }
}
