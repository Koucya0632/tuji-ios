// 搜尋 (§III.J) — the model behind the screen.
//
// Local-first: the full dictionary already lives in `WordsStore`, so every
// keystroke filters in-memory and shows results instantly (works offline, no
// debounce wait). In parallel a debounced GET /api/search runs to supplement
// with matches the local list can't see (synonyms / also-known-as / fuzzy); its
// results are merged in + deduped when they arrive.
//
// It used to live at the top of `SearchView.swift` and reach `WordsStore.shared`
// at three call sites and `LocalCache.shared` at a fourth, from inside its own
// methods. The cost was not hypothetical: `SearchVMTests` had seven tests and
// **not one of them constructed a `SearchVM`** — every assertion went to the two
// `static` ranking functions, which are the only part a test could reach.
// Everything the user actually experiences here — the debounce, the cancel, the
// stale-answer guard, when an error is allowed to replace results, and what
// counts as worth remembering — was verified by nothing.
//
// *The interface is the test surface.* Tests that have to enter where the app
// doesn't are telling you the module is the wrong shape — the lesson `StudyLadder`
// already recorded. And a module named after one of its callers does not get
// found by the next one, which is why this is no longer inside `SearchView.swift`.

import OSLog
import Observation
import SwiftUI

/// The local dictionary as 搜尋 reads it: the whole in-memory catalog, live at
/// call time. A read seam in the shape `LanguageContext` already uses — narrow,
/// injected, conformed by the store that holds the real thing.
@MainActor
protocol LocalDictionaryReading {
    var words: [CardWord] { get }
}

/// Remembering a query. Separate from the dictionary because it is a *write*,
/// and because the rule worth pinning is when it does not happen.
@MainActor
protocol RecentSearchWriting {
    func pushRecentSearch(_ q: String)
}

extension WordsStore: LocalDictionaryReading {}

extension LocalCache: RecentSearchWriting {}

@MainActor
@Observable
final class SearchVM {
    /// `@MainActor` deliberately: the debounce runs in a `Task` spawned from an
    /// isolated method, so it inherits this actor either way — and saying so
    /// lets an injected recorder be a plain `@MainActor` object rather than
    /// something that has to be `Sendable` to count sleeps.
    typealias Sleep = @MainActor (Duration) async -> Void

    var query: String = ""
    var results: [CardWord] = []
    var loading: Bool = false
    var lastError: Error?
    var lastQuery: String = ""

    private var task: Task<Void, Never>?
    private let repository: CatalogRepository
    private let dictionary: LocalDictionaryReading
    private let recents: RecentSearchWriting
    private let debounce: Duration
    private let sleep: Sleep
    private let log = Logger(subsystem: "app.tuji.ios", category: "search")

    init(
        repository: CatalogRepository = LiveCatalogRepository.shared,
        dictionary: LocalDictionaryReading = WordsStore.shared,
        recents: RecentSearchWriting = LocalCache.shared,
        debounce: Duration = .milliseconds(250),
        sleep: @escaping Sleep = { try? await Task.sleep(for: $0) }
    ) {
        self.repository = repository
        self.dictionary = dictionary
        self.recents = recents
        self.debounce = debounce
        self.sleep = sleep
    }

    func updateQuery(_ q: String) {
        self.query = q
        self.task?.cancel()
        let trimmed = q.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            self.results = []
            self.lastError = nil
            self.lastQuery = ""
            self.loading = false
            return
        }
        self.showLocalResults(for: trimmed)
        // Debounced server search to supplement the local hits.
        self.task = Task { [weak self] in
            guard let self else { return }
            await self.sleep(self.debounce)
            guard !Task.isCancelled else { return }
            await self.runSearch(trimmed)
        }
    }

    /// Re-run a known query immediately (no debounce) — used when the user taps
    /// a "recent searches" row.
    func runImmediately(_ q: String) {
        self.task?.cancel()
        let trimmed = q.trimmingCharacters(in: .whitespaces)
        self.query = q
        self.showLocalResults(for: trimmed)
        self.task = Task { [weak self] in
            await self?.runSearch(trimmed)
        }
    }

    /// Await whatever is in flight.
    ///
    /// A seam reaches only as far as a test can await (ADR-0001, amendment note
    /// 2). The debounce is the one piece of work this module has to own rather
    /// than hand to the View — a `TextField` cannot own a task per keystroke —
    /// so it owes callers a way to settle, exactly as 生成佇列 does.
    func settle() async {
        await self.task?.value
    }

    // MARK: - Internals

    /// Instant local results — no waiting on the network. Also the point where
    /// the query being answered is recorded, so `lastQuery` always describes
    /// what is on screen rather than what the network is still fetching.
    private func showLocalResults(for trimmed: String) {
        self.results = Self.localMatches(trimmed, in: self.dictionary.words)
        self.lastQuery = trimmed
        self.lastError = nil
    }

    /// Has the user moved on since this request went out?
    ///
    /// One guard, checked once. It used to be written twice — the same
    /// expression in the success path and again in the `catch` — which is two
    /// chances to disagree about what "still current" means.
    private func isCurrent(_ q: String) -> Bool {
        q == self.query.trimmingCharacters(in: .whitespaces)
    }

    private func runSearch(_ q: String) async {
        self.loading = true
        defer { self.loading = false }

        let outcome: Result<SearchResponse, Error>
        do {
            outcome = try await .success(self.repository.search(q))
        } catch {
            outcome = .failure(error)
        }
        // Drop a stale answer whichever way it came back: the user kept typing,
        // so this is about a question no longer on screen.
        guard self.isCurrent(q) else { return }

        switch outcome {
        case let .success(resp):
            self.results = Self.merge(
                local: Self.localMatches(q, in: self.dictionary.words),
                remote: resp.results
            )
            self.lastQuery = q
            self.lastError = nil
            self.log.info(
                "search '\(q, privacy: .public)' → \(self.results.count, privacy: .public) results"
            )
            // Only a query that found something is worth offering again. A
            // recent-search row that reliably returns nothing is worse than no
            // row at all.
            if !self.results.isEmpty {
                self.recents.pushRecentSearch(q)
            }
        case let .failure(error):
            // Keep the instant local results on screen; only surface the error
            // when there's nothing to show. A network failure is not a reason to
            // throw away answers the device already had.
            if self.results.isEmpty {
                self.lastError = error
            }
            self.log.error(
                "search '\(q, privacy: .public)' failed: \(error.localizedDescription, privacy: .public)"
            )
        }
    }

    // MARK: - Matching

    /// Case-insensitive ranked match over the supplied dictionary. Looks at
    /// English word, Chinese gloss, and pronunciation. Closer matches
    /// (exact → prefix → contains) and shorter words sort first.
    static func localMatches(_ q: String, in words: [CardWord]) -> [CardWord] {
        let needle = q.lowercased()
        guard !needle.isEmpty else { return [] }
        return words
            .compactMap { w -> (word: CardWord, rank: Int)? in
                let word = w.word.lowercased()
                let zh = w.chinese.lowercased()
                let pron = w.pronunciation.lowercased()
                let reading = w.reading?.lowercased() ?? ""
                let rank: Int
                if word == needle { rank = 0 }
                else if word.hasPrefix(needle) { rank = 1 }
                else if zh.hasPrefix(needle) { rank = 2 }
                else if word.contains(needle) { rank = 3 }
                else if zh.contains(needle) { rank = 4 }
                else if reading.contains(needle) { rank = 5 }
                else if pron.contains(needle) { rank = 6 }
                else { return nil }
                return (w, rank)
            }
            .sorted { a, b in
                a.rank != b.rank ? a.rank < b.rank : a.word.word.count < b.word.word.count
            }
            .map(\.word)
    }

    /// Local hits first (already ranked), then any remote-only matches, deduped
    /// by id.
    static func merge(local: [CardWord], remote: [CardWord]) -> [CardWord] {
        var seen = Set<String>()
        var out: [CardWord] = []
        for w in local + remote where seen.insert(w.id).inserted {
            out.append(w)
        }
        return out
    }
}
