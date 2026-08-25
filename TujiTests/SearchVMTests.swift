// Pins SearchVM's local ranking (exact → prefix → contains, shorter first), the
// local-first merge/dedupe the search screen builds on, and — new — the module
// itself.
//
// The ranking tests below are unchanged. What they never covered is everything
// between a keystroke and what lands on screen: the debounce, the cancel, the
// stale-answer guard, when an error is allowed to replace results, and what
// counts as a query worth remembering. Those five could not be reached, because
// `SearchVM` read `WordsStore.shared` / `LocalCache.shared` from inside its own
// methods, so **not one of the seven tests here constructed a `SearchVM`**. Now
// they go through the same entry points the View uses.

import Foundation
import Testing
@testable import Tuji

struct SearchVMTests {
    private func word(
        _ id: String,
        word: String,
        chinese: String = "",
        pronunciation: String = "",
        reading: String? = nil
    )
        -> CardWord
    {
        CardWord(
            id: id,
            word: word,
            chinese: chinese,
            imageUrl: "",
            category: "test",
            pronunciation: pronunciation,
            reading: reading
        )
    }

    @Test
    func ranksExactBeforePrefixBeforeContains() {
        let words = [
            self.word("contains", word: "wildcat"),
            self.word("prefix", word: "catalog"),
            self.word("exact", word: "cat"),
            self.word("miss", word: "dog")
        ]
        let hits = SearchVM.localMatches("cat", in: words)
        #expect(hits.map(\.id) == ["exact", "prefix", "contains"])
    }

    @Test
    func shorterWordWinsWithinSameRank() {
        let words = [
            self.word("long", word: "catalog"),
            self.word("short", word: "cats")
        ]
        let hits = SearchVM.localMatches("cat", in: words)
        #expect(hits.map(\.id) == ["short", "long"])
    }

    @Test
    func matchesChineseGloss() {
        let words = [
            self.word("zh-contains", word: "wildcat", chinese: "野貓"),
            self.word("zh-prefix", word: "cat", chinese: "貓")
        ]
        let hits = SearchVM.localMatches("貓", in: words)
        #expect(hits.map(\.id) == ["zh-prefix", "zh-contains"])
    }

    @Test
    func matchesKanaReading() {
        let words = [self.word("ja", word: "猫", chinese: "貓", reading: "ねこ")]
        #expect(SearchVM.localMatches("ねこ", in: words).map(\.id) == ["ja"])
    }

    @Test
    func emptyQueryReturnsNothing() {
        let words = [self.word("any", word: "cat")]
        #expect(SearchVM.localMatches("", in: words).isEmpty)
    }

    @Test
    func mergeKeepsLocalOrderAndDedupes() {
        let local = [self.word("a", word: "apple"), self.word("b", word: "banana")]
        let remote = [self.word("b", word: "banana"), self.word("c", word: "cherry")]
        let merged = SearchVM.merge(local: local, remote: remote)
        #expect(merged.map(\.id) == ["a", "b", "c"])
    }
}

// MARK: - The module itself

/// Everything between a keystroke and what lands on screen. None of this was
/// reachable while the dictionary and the recent-search list were `.shared`
/// reads inside the methods.
@MainActor
struct SearchVMBehaviourTests {
    private func word(_ id: String, _ text: String) -> CardWord {
        CardWord(
            id: id,
            word: text,
            chinese: "",
            imageUrl: "",
            category: "test",
            pronunciation: "",
            reading: nil
        )
    }

    /// No real waiting: the debounce is an injected `sleep`, so a test pins
    /// *that it is awaited* without spending 250 ms per assertion.
    private func makeVM(
        dictionary: [CardWord] = [],
        repo: FakeSearchRepository,
        recents: SpyRecentSearches = SpyRecentSearches(),
        sleeps: SleepRecorder? = nil
    )
        -> SearchVM
    {
        SearchVM(
            repository: repo,
            dictionary: FakeDictionary(words: dictionary),
            recents: recents,
            sleep: { duration in sleeps?.record(duration) }
        )
    }

    // MARK: Local-first

    /// Local matching is synchronous — no `await` in this test, which is the
    /// whole point: 搜尋 works offline and never waits on a spinner to show what
    /// the device already knows.
    @Test
    func aKeystrokeShowsLocalResultsBeforeTheNetworkAnswers() async {
        let repo = FakeSearchRepository()
        let vm = self.makeVM(dictionary: [self.word("cat", "cat")], repo: repo)

        vm.updateQuery("cat")

        #expect(vm.results.map(\.id) == ["cat"])
        await vm.settle()
    }

    @Test
    func clearingTheQueryClearsEverything() async {
        let repo = FakeSearchRepository()
        let vm = self.makeVM(dictionary: [self.word("cat", "cat")], repo: repo)
        vm.updateQuery("cat")
        await vm.settle()

        vm.updateQuery("")

        #expect(vm.results.isEmpty)
        #expect(vm.lastQuery.isEmpty)
        #expect(vm.lastError == nil)
        #expect(!vm.loading)
    }

    /// Whitespace is not a query — it must not cost a request.
    @Test
    func aWhitespaceOnlyQueryIsTreatedAsEmpty() async {
        let repo = FakeSearchRepository()
        let vm = self.makeVM(dictionary: [self.word("cat", "cat")], repo: repo)

        vm.updateQuery("   ")
        await vm.settle()

        #expect(vm.results.isEmpty)
        #expect(vm.lastQuery.isEmpty)
        #expect(repo.queries.isEmpty)
    }

    // MARK: Debounce & cancellation

    /// The debounce is awaited before the request goes out — otherwise every
    /// keystroke is a paid round trip.
    @Test
    func theServerRequestWaitsForTheDebounce() async {
        let repo = FakeSearchRepository()
        let sleeps = SleepRecorder()
        let vm = self.makeVM(repo: repo, sleeps: sleeps)

        vm.updateQuery("cat")
        await vm.settle()

        #expect(sleeps.durations == [.milliseconds(250)])
        #expect(repo.queries == ["cat"])
    }

    /// Typing again cancels the pending request: four keystrokes are not four
    /// searches.
    @Test
    func typingAgainCancelsThePendingRequest() async {
        let repo = FakeSearchRepository()
        let vm = self.makeVM(repo: repo)

        vm.updateQuery("c")
        vm.updateQuery("ca")
        vm.updateQuery("cat")
        await vm.settle()

        #expect(repo.queries == ["cat"])
    }

    /// Tapping a recent search skips the debounce — the user already committed
    /// to the query, so making them wait for it is pure latency.
    @Test
    func aRecentSearchRunsWithoutWaiting() async {
        let repo = FakeSearchRepository()
        let sleeps = SleepRecorder()
        let vm = self.makeVM(repo: repo, sleeps: sleeps)

        vm.runImmediately("cat")
        await vm.settle()

        #expect(sleeps.durations.isEmpty)
        #expect(repo.queries == ["cat"])
    }

    // MARK: Staleness

    /// A slow answer to an abandoned query must not overwrite the current one.
    /// The guard used to be written twice — once in the success path and again
    /// in the `catch` — which is two chances to disagree about "still current".
    @Test
    func aStaleAnswerDoesNotOverwriteTheCurrentResults() async {
        let repo = FakeSearchRepository()
        repo.responses["cat"] = .success([self.word("remote-cat", "cat")])
        let vm = self.makeVM(dictionary: [self.word("dog", "dog")], repo: repo)
        // The user types "dog" while the "cat" request is still in flight.
        repo.onSearch = { q in if q == "cat" { vm.updateQuery("dog") } }

        vm.updateQuery("cat")
        await vm.settle() // the "cat" task
        await vm.settle() // the "dog" task it spawned mid-flight

        #expect(vm.lastQuery == "dog")
        #expect(!vm.results.contains { $0.id == "remote-cat" })
    }

    /// Same rule on the failure side: a stale *error* must not blank a screen
    /// that is now showing results for something else.
    @Test
    func aStaleFailureDoesNotSurfaceAnError() async {
        let repo = FakeSearchRepository()
        repo.responses["cat"] = .failure(FakeSearchError.boom)
        let vm = self.makeVM(dictionary: [self.word("dog", "dog")], repo: repo)
        repo.onSearch = { q in if q == "cat" { vm.updateQuery("dog") } }

        vm.updateQuery("cat")
        await vm.settle()
        await vm.settle()

        #expect(vm.lastError == nil)
        #expect(vm.lastQuery == "dog")
    }

    // MARK: Errors

    /// A network failure is not a reason to throw away answers the device
    /// already had.
    @Test
    func aFailureWithLocalResultsOnScreenStaysSilent() async {
        let repo = FakeSearchRepository()
        repo.responses["cat"] = .failure(FakeSearchError.boom)
        let vm = self.makeVM(dictionary: [self.word("cat", "cat")], repo: repo)

        vm.updateQuery("cat")
        await vm.settle()

        #expect(vm.lastError == nil)
        #expect(vm.results.map(\.id) == ["cat"])
    }

    /// With nothing to show, the error is the only honest thing on screen.
    @Test
    func aFailureWithNothingToShowSurfacesTheError() async {
        let repo = FakeSearchRepository()
        repo.responses["cat"] = .failure(FakeSearchError.boom)
        let vm = self.makeVM(dictionary: [], repo: repo)

        vm.updateQuery("cat")
        await vm.settle()

        #expect(vm.lastError != nil)
    }

    @Test
    func loadingClearsAfterAFailure() async {
        let repo = FakeSearchRepository()
        repo.responses["cat"] = .failure(FakeSearchError.boom)
        let vm = self.makeVM(repo: repo)

        vm.updateQuery("cat")
        await vm.settle()

        #expect(!vm.loading)
    }

    // MARK: Recent searches

    /// Only a query that found something is worth offering again — a
    /// recent-search row that reliably returns nothing is worse than no row.
    @Test
    func onlyAQueryThatFoundSomethingIsRemembered() async {
        let recents = SpyRecentSearches()
        let repo = FakeSearchRepository()
        repo.responses["cat"] = .success([self.word("remote-cat", "cat")])
        repo.responses["zzz"] = .success([])
        let vm = self.makeVM(repo: repo, recents: recents)

        vm.updateQuery("cat")
        await vm.settle()
        vm.updateQuery("zzz")
        await vm.settle()

        #expect(recents.pushed == ["cat"])
    }

    /// A failed search remembers nothing, even with local results on screen:
    /// the list is 「找得到的字」, not 「你打過的字」.
    @Test
    func aFailedSearchIsNotRemembered() async {
        let recents = SpyRecentSearches()
        let repo = FakeSearchRepository()
        repo.responses["cat"] = .failure(FakeSearchError.boom)
        let vm = self.makeVM(dictionary: [self.word("cat", "cat")], repo: repo, recents: recents)

        vm.updateQuery("cat")
        await vm.settle()

        #expect(recents.pushed.isEmpty)
    }

    // MARK: Merge

    @Test
    func remoteResultsSupplementTheLocalOnesWithoutDuplicating() async {
        let repo = FakeSearchRepository()
        repo.responses["cat"] = .success([self.word("cat", "cat"), self.word("kitty", "kitty")])
        let vm = self.makeVM(dictionary: [self.word("cat", "cat")], repo: repo)

        vm.updateQuery("cat")
        await vm.settle()

        #expect(vm.results.map(\.id) == ["cat", "kitty"])
    }
}

// MARK: - Fakes

enum FakeSearchError: Error { case boom }

@MainActor
final class FakeDictionary: LocalDictionaryReading {
    var words: [CardWord]

    init(words: [CardWord]) {
        self.words = words
    }
}

@MainActor
final class SpyRecentSearches: RecentSearchWriting {
    private(set) var pushed: [String] = []

    func pushRecentSearch(_ q: String) {
        self.pushed.append(q)
    }
}

@MainActor
final class SleepRecorder {
    private(set) var durations: [Duration] = []

    func record(_ duration: Duration) {
        self.durations.append(duration)
    }
}

@MainActor
final class FakeSearchRepository: CatalogRepository {
    var responses: [String: Result<[CardWord], Error>] = [:]
    /// Runs while a request is in flight, so "the user typed again mid-request"
    /// is a state a test can deterministically be in.
    var onSearch: ((String) -> Void)?
    private(set) var queries: [String] = []

    struct NotImplemented: Error {}

    func search(_ query: String) async throws -> SearchResponse {
        self.queries.append(query)
        self.onSearch?(query)
        switch self.responses[query] {
        case let .success(words): return SearchResponse(results: words, query: query, limit: nil)
        case let .failure(error): throw error
        case nil: return SearchResponse(results: [], query: query, limit: nil)
        }
    }

    func loadCategories(lang _: String) async throws -> CategoriesResponse {
        throw NotImplemented()
    }

    func loadWords(lang _: String, learning _: String) async throws -> WordsListResponse {
        throw NotImplemented()
    }

    func loadCustomWords(lang _: String, learning _: String) async throws -> WordsListResponse {
        throw NotImplemented()
    }

    func loadSavedWords(lang _: String, learning _: String) async throws -> WordsListResponse {
        throw NotImplemented()
    }

    func word(id _: String, lang _: String, learning _: String) async throws -> Word {
        throw NotImplemented()
    }
}
