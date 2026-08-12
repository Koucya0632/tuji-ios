// Single source of truth for the entire word dictionary client-side.
//
// Calls GET /api/words once at app launch, keeps the array in memory,
// and exposes filter/lookup helpers so every screen (Cards, Today,
// Search, Favorites, etc.) reads the same data without re-fetching.
//
// The backend response is next-cache wrapped, so a fresh load is cheap;
// we still cache locally to avoid the network round trip after the
// first call. Failure leaves `words` empty + sets `lastError`; the UI
// can offer a retry via `reload()`.

import Foundation
import Observation
import OSLog

@MainActor
@Observable
final class WordsStore {
    static let shared = WordsStore()

    private(set) var words: [CardWord] = []
    private(set) var loading: Bool = false
    private(set) var lastError: Error?

    /// True once the first load attempt has finished (success *or* failure).
    /// Used by the splash gate so a failed load doesn't trap us on Splash.
    private(set) var loaded: Bool = false

    private let repository: CatalogRepository
    private let log = Logger(subsystem: "app.tuji.ios", category: "words")

    /// Per-selection dictionary counts; see `count(inCategories:)`.
    /// `@ObservationIgnored` because a memo is not state anyone observes.
    @ObservationIgnored private var countByCategories: [String: Int] = [:]
    @ObservationIgnored private var latestRequestedContext: CatalogContext?
    @ObservationIgnored private var loadedContext: CatalogContext?
    @ObservationIgnored private var inFlight: [CatalogContext: LoadFlight] = [:]
    @ObservationIgnored private var publicCache: [PublicKey: [CardWord]] = [:]
    @ObservationIgnored private var publicInFlight: [PublicKey: PublicFlight] = [:]

    private struct LoadFlight {
        let id: UUID
        let task: Task<Void, Never>
    }

    private struct PublicKey: Hashable {
        let contentLanguageCode: String
        let learningDirectionCode: String
    }

    private struct PublicFlight {
        let id: UUID
        let task: Task<Result<[CardWord], Error>, Never>
    }

    private struct LoadedWords {
        let words: [CardWord]
        let customError: Error?
        let savedError: Error?
    }

    init(repository: CatalogRepository = LiveCatalogRepository.shared) {
        self.repository = repository
    }

    /// Returns immediately if we already have words. Triggers a fresh
    /// network load otherwise.
    func loadIfNeeded() async {
        await self.loadIfNeeded(for: CatalogContext.current())
    }

    /// Joins an in-flight request for the same immutable context. A successful
    /// empty catalog is still considered warm; failed attempts remain retryable.
    func loadIfNeeded(for context: CatalogContext) async {
        guard self.loadedContext != context || !self.loaded || self.lastError != nil else { return }
        await self.load(for: context, reusePublic: true)
    }

    func reload() async {
        await self.reload(for: CatalogContext.current())
    }

    /// Forces a refresh for `context`, while coalescing concurrent refreshes
    /// for that same context. Different contexts may load concurrently, but
    /// only the most recently requested context is allowed to publish state.
    func reload(for context: CatalogContext) async {
        await self.load(for: context, reusePublic: false)
    }

    private func load(for context: CatalogContext, reusePublic: Bool) async {
        self.latestRequestedContext = context
        self.loading = true
        self.lastError = nil

        if let flight = self.inFlight[context] {
            await flight.task.value
            return
        }

        let flightID = UUID()
        let task = Task { [weak self] in
            guard let self else { return }
            await self.performReload(
                for: context,
                flightID: flightID,
                reusePublic: reusePublic
            )
        }
        self.inFlight[context] = LoadFlight(id: flightID, task: task)
        await task.value

        if self.inFlight[context]?.id == flightID {
            self.inFlight[context] = nil
        }
        self.refreshLoadingState()
    }

    private func performReload(
        for context: CatalogContext,
        flightID: UUID,
        reusePublic: Bool
    ) async {
        let result = await self.fetchWords(for: context, reusePublic: reusePublic)
        guard self.latestRequestedContext == context,
              self.inFlight[context]?.id == flightID
        else { return }

        self.loadedContext = context
        self.loaded = true
        switch result {
        case let .success(payload):
            self.words = payload.words
            self.countByCategories.removeAll()
            if let error = payload.customError {
                self.log.info("custom words skipped: \(error.localizedDescription, privacy: .public)")
            }
            if let error = payload.savedError {
                self.log.info("saved words skipped: \(error.localizedDescription, privacy: .public)")
            }
            self.log.info("loaded \(payload.words.count, privacy: .public) words")
        case let .failure(error):
            // Preserve the last good snapshot. Existing screens can keep using
            // it while exposing the retry state through `lastError`.
            self.lastError = error
            self.log.error("words load failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Starts all eligible sources together. Public is required; custom and
    /// saved are independent optional overlays whose failures stay non-fatal.
    private func fetchWords(
        for context: CatalogContext,
        reusePublic: Bool
    ) async
        -> Result<LoadedWords, Error>
    {
        async let publicResult = self.fetchPublicWords(for: context, reuseCached: reusePublic)
        async let customResult = self.fetchCustomWords(for: context)
        async let savedResult = self.fetchSavedWords(for: context)

        let (publicWords, customWords, savedWords) = await (publicResult, customResult, savedResult)

        do {
            let publicWords = try publicWords.get()
            let custom = Self.optionalSource(customWords)
            let saved = Self.optionalSource(savedWords)
            return .success(
                LoadedWords(
                    words: Self.merge(
                        publicWords: publicWords,
                        customWords: custom.words,
                        savedWords: saved.words
                    ),
                    customError: custom.error,
                    savedError: saved.error
                )
            )
        } catch {
            return .failure(error)
        }
    }

    private func fetchPublicWords(
        for context: CatalogContext,
        reuseCached: Bool
    ) async
        -> Result<[CardWord], Error>
    {
        let key = PublicKey(
            contentLanguageCode: context.contentLanguageCode,
            learningDirectionCode: context.learningDirectionCode
        )
        if reuseCached, let cached = self.publicCache[key] {
            return .success(cached)
        }
        if let flight = self.publicInFlight[key] {
            return await flight.task.value
        }

        let flightID = UUID()
        let repository = self.repository
        let task = Task { () -> Result<[CardWord], Error> in
            do {
                let response = try await repository.loadWords(
                    lang: key.contentLanguageCode,
                    learning: key.learningDirectionCode
                )
                return .success(response.words)
            } catch {
                return .failure(error)
            }
        }
        self.publicInFlight[key] = PublicFlight(id: flightID, task: task)
        let result = await task.value
        let flightIsCurrent = self.publicInFlight[key]?.id == flightID
        if flightIsCurrent {
            self.publicInFlight[key] = nil
        }
        if flightIsCurrent, case let .success(words) = result {
            self.publicCache[key] = words
        }
        return result
    }

    private func fetchCustomWords(for context: CatalogContext) async -> Result<[CardWord], Error> {
        guard context.includePersonalization else { return .success([]) }
        do {
            let response = try await self.repository.loadCustomWords(
                lang: context.contentLanguageCode,
                learning: context.learningDirectionCode
            )
            return .success(response.words)
        } catch {
            return .failure(error)
        }
    }

    private func fetchSavedWords(for context: CatalogContext) async -> Result<[CardWord], Error> {
        guard context.includePersonalization else { return .success([]) }
        do {
            let response = try await self.repository.loadSavedWords(
                lang: context.contentLanguageCode,
                learning: context.learningDirectionCode
            )
            return .success(response.words)
        } catch {
            return .failure(error)
        }
    }

    private static func optionalSource(_ result: Result<[CardWord], Error>)
        -> (words: [CardWord], error: Error?)
    {
        switch result {
        case let .success(words): (words, nil)
        case let .failure(error): ([], error)
        }
    }

    private func refreshLoadingState() {
        guard let latestRequestedContext else {
            self.loading = false
            return
        }
        self.loading = self.inFlight[latestRequestedContext] != nil
    }

    func invalidate() {
        self.latestRequestedContext = nil
        self.loadedContext = nil
        for flight in self.inFlight.values {
            flight.task.cancel()
        }
        for flight in self.publicInFlight.values {
            flight.task.cancel()
        }
        self.inFlight.removeAll()
        self.publicInFlight.removeAll()
        self.publicCache.removeAll()
        self.words = []
        self.countByCategories.removeAll()
        self.loading = false
        self.loaded = false
    }

    // MARK: - Filters

    func byCategory(_ id: String?) -> [CardWord] {
        guard let id else { return self.words }
        return self.words.filter { $0.category == id }
    }

    func byIds(_ ids: Set<String>) -> [CardWord] {
        self.words.filter { ids.contains($0.id) }
    }

    func find(id: String) -> CardWord? {
        self.words.first { $0.id == id }
    }

    /// All unique category ids represented in the current dataset.
    var categories: [String] {
        Array(Set(self.words.map(\.category))).sorted()
    }

    /// Internal (not private) so unit tests can exercise the last-wins/sort rules.
    static func merge(publicWords: [CardWord], customWords: [CardWord]) -> [CardWord] {
        self.merge(publicWords: publicWords, customWords: customWords, savedWords: [])
    }

    /// Overlay precedence is fixed regardless of network completion order:
    /// public < custom < saved, with later sources winning duplicate ids.
    static func merge(
        publicWords: [CardWord],
        customWords: [CardWord],
        savedWords: [CardWord]
    )
        -> [CardWord]
    {
        // Last-wins by id. Built with a loop rather than
        // Dictionary(uniqueKeysWithValues:), which traps fatally if the server
        // ever returns a duplicate id in the public list.
        var byId: [String: CardWord] = [:]
        for word in publicWords {
            byId[word.id] = word
        }
        for word in customWords {
            byId[word.id] = word
        }
        for word in savedWords {
            byId[word.id] = word
        }
        return Array(byId.values).sorted {
            if $0.category != $1.category { return $0.category < $1.category }
            return $0.word.localizedCaseInsensitiveCompare($1.word) == .orderedAscending
        }
    }

    /// How many dictionary words fall inside a 學習主題 selection.
    ///
    /// Memoised: this is an O(dictionary) scan — ~480 words — and 首頁 asks for
    /// it through `TodayDecisions`, a *computed* property re-read about a dozen
    /// times in one `body` evaluation. 我 · 進度 hand-writes the same scan for
    /// the same number. The cache clears whenever `words` is replaced.
    func count(inCategories categories: [String]) -> Int {
        let key = categories.sorted().joined(separator: "\u{1F}")
        if let cached = countByCategories[key] { return cached }
        let wanted = Set(categories)
        let count = self.words.count { wanted.contains($0.category) }
        self.countByCategories[key] = count
        return count
    }
}
