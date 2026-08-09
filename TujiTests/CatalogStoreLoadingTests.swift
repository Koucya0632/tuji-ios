import Foundation
import Testing
@testable import Tuji

@Suite(.serialized)
@MainActor
struct CatalogStoreLoadingTests {
    @Test
    func wordsCoalesceSameContext() async {
        let repository = CatalogRepositoryFake()
        let gate = AsyncResultGate<WordsListResponse>()
        repository.wordsHandler = { _, _ in try await gate.wait() }
        let store = WordsStore(repository: repository)
        let context = self.context(language: "zh-Hant")

        let first = Task { await store.loadIfNeeded(for: context) }
        await waitUntil { repository.wordCalls.count == 1 }
        let second = Task { await store.loadIfNeeded(for: context) }
        await Task.yield()

        #expect(repository.wordCalls.count == 1)
        gate.succeed(self.wordsResponse([self.word("public")]))
        await first.value
        await second.value

        #expect(repository.wordCalls.count == 1)
        #expect(store.words.map(\.id) == ["public"])
        #expect(store.loaded)
        #expect(!store.loading)
    }

    @Test
    func cancelledFlightCannotPublishIntoSameContextReplacement() async {
        let repository = CatalogRepositoryFake()
        let oldGate = AsyncResultGate<WordsListResponse>()
        let replacementGate = AsyncResultGate<WordsListResponse>()
        repository.wordsHandler = { _, _ in
            if repository.wordCalls.count == 1 {
                return try await oldGate.wait()
            }
            return try await replacementGate.wait()
        }
        let store = WordsStore(repository: repository)
        let context = self.context(language: "zh-Hant")

        let oldLoad = Task { await store.reload(for: context) }
        await waitUntil { repository.wordCalls.count == 1 }
        store.invalidate()
        let replacementLoad = Task { await store.reload(for: context) }
        await waitUntil { repository.wordCalls.count == 2 }

        replacementGate.succeed(self.wordsResponse([self.word("new")]))
        await replacementLoad.value
        oldGate.fail(TestFailure.boom)
        await oldLoad.value

        #expect(store.words.map(\.id) == ["new"])
        #expect(store.lastError == nil)
        #expect(store.loaded)
        #expect(!store.loading)
    }

    @Test
    func anonymousAndPersonalizedAggregatesReuseOnlyTheirPublicSource() async {
        let repository = CatalogRepositoryFake()
        let anonymousGate = AsyncResultGate<WordsListResponse>()
        repository.wordsHandler = { _, _ in
            try await anonymousGate.wait()
        }
        repository.customHandler = { [self] _, _ in
            self.wordsResponse([self.word("same", label: "personal")])
        }
        let store = WordsStore(repository: repository)
        let anonymous = self.context(language: "zh-Hant")
        let personalized = self.context(
            language: "zh-Hant",
            userID: UUID(),
            includePersonalization: true
        )

        let anonymousLoad = Task { await store.reload(for: anonymous) }
        await waitUntil { repository.wordCalls.count == 1 }
        let personalizedLoad = Task { await store.loadIfNeeded(for: personalized) }
        await waitUntil {
            repository.customCalls.count == 1 && repository.savedCalls.count == 1
        }

        // The aggregate flights differ, so personalized sources run, while the
        // identical public request is safely reused.
        #expect(repository.wordCalls.count == 1)

        anonymousGate.succeed(self.wordsResponse([self.word("same", label: "public")]))
        await personalizedLoad.value
        await anonymousLoad.value

        #expect(repository.wordCalls.count == 1)
        #expect(store.words.map(\.word) == ["personal"])
    }

    @Test
    func wordSourcesStartTogetherAndMergeInFixedOrder() async {
        let repository = CatalogRepositoryFake()
        let publicGate = AsyncResultGate<WordsListResponse>()
        let customGate = AsyncResultGate<WordsListResponse>()
        let savedGate = AsyncResultGate<WordsListResponse>()
        repository.wordsHandler = { _, _ in try await publicGate.wait() }
        repository.customHandler = { _, _ in try await customGate.wait() }
        repository.savedHandler = { _, _ in try await savedGate.wait() }
        let store = WordsStore(repository: repository)
        let context = self.context(
            language: "zh-Hant",
            userID: UUID(),
            includePersonalization: true
        )

        let load = Task { await store.reload(for: context) }
        await waitUntil {
            repository.wordCalls.count == 1 &&
                repository.customCalls.count == 1 &&
                repository.savedCalls.count == 1
        }

        // Completion order is deliberately the inverse of merge precedence.
        savedGate.succeed(self.wordsResponse([self.word("same", label: "saved")]))
        customGate.succeed(self.wordsResponse([self.word("same", label: "custom")]))
        publicGate.succeed(self.wordsResponse([self.word("same", label: "public")]))
        await load.value

        #expect(store.words.map(\.word) == ["saved"])
        #expect(store.lastError == nil)
    }

    @Test
    func optionalWordSourceFailureKeepsSuccessfulSources() async {
        let repository = CatalogRepositoryFake()
        repository.wordsHandler = { [self] _, _ in
            self.wordsResponse([self.word("public")])
        }
        repository.customHandler = { _, _ in throw TestFailure.boom }
        repository.savedHandler = { [self] _, _ in
            self.wordsResponse([self.word("saved")])
        }
        let store = WordsStore(repository: repository)
        let context = self.context(
            language: "zh-Hant",
            userID: UUID(),
            includePersonalization: true
        )

        await store.reload(for: context)

        #expect(store.words.map(\.id) == ["public", "saved"])
        #expect(store.lastError == nil)
        #expect(store.loaded)
    }

    @Test
    func requiredPublicWordFailureCanRetry() async {
        let repository = CatalogRepositoryFake()
        repository.wordsHandler = { [self] _, _ in
            if repository.wordCalls.count == 1 {
                throw TestFailure.boom
            }
            return self.wordsResponse([self.word("recovered")])
        }
        let store = WordsStore(repository: repository)
        let context = self.context(language: "zh-Hant")

        await store.loadIfNeeded(for: context)

        #expect(store.loaded)
        #expect(store.lastError != nil)
        #expect(store.words.isEmpty)

        await store.loadIfNeeded(for: context)

        #expect(repository.wordCalls.count == 2)
        #expect(store.lastError == nil)
        #expect(store.words.map(\.id) == ["recovered"])
    }

    @Test
    func categoriesDiscardLateObsoleteContext() async {
        let repository = CatalogRepositoryFake()
        let oldGate = AsyncResultGate<CategoriesResponse>()
        let newGate = AsyncResultGate<CategoriesResponse>()
        repository.categoriesHandler = { lang in
            if lang == "old" { return try await oldGate.wait() }
            return try await newGate.wait()
        }
        let store = CategoriesStore(repository: repository)
        let oldContext = self.context(language: "old")
        let newContext = self.context(language: "new")

        let oldLoad = Task { await store.reload(for: oldContext) }
        await waitUntil { repository.categoryCalls == ["old"] }
        let newLoad = Task { await store.reload(for: newContext) }
        await waitUntil { repository.categoryCalls == ["old", "new"] }

        newGate.succeed(CategoriesResponse(categories: [self.category("new")]))
        await newLoad.value
        oldGate.succeed(CategoriesResponse(categories: [self.category("old")]))
        await oldLoad.value

        #expect(store.categories.map(\.id) == ["new"])
        #expect(store.loaded)
        #expect(!store.loading)
    }

    @Test
    func categoriesCoalesceSameContext() async {
        let repository = CatalogRepositoryFake()
        let gate = AsyncResultGate<CategoriesResponse>()
        repository.categoriesHandler = { _ in try await gate.wait() }
        let store = CategoriesStore(repository: repository)
        let context = self.context(language: "zh-Hant")

        let first = Task { await store.loadIfNeeded(for: context) }
        await waitUntil { repository.categoryCalls.count == 1 }
        let second = Task { await store.loadIfNeeded(for: context) }
        await Task.yield()

        #expect(repository.categoryCalls.count == 1)
        gate.succeed(CategoriesResponse(categories: [self.category("one")]))
        await first.value
        await second.value

        #expect(repository.categoryCalls.count == 1)
        #expect(store.categories.map(\.id) == ["one"])
    }

    @Test
    func categoriesReuseAnonymousSourceForPersonalizedContext() async {
        let repository = CatalogRepositoryFake()
        repository.categoriesHandler = { [self] _ in
            CategoriesResponse(categories: [self.category("one")])
        }
        let store = CategoriesStore(repository: repository)
        let anonymous = self.context(language: "zh-Hant")
        let personalized = self.context(
            language: "zh-Hant",
            userID: UUID(),
            includePersonalization: true
        )

        await store.loadIfNeeded(for: anonymous)
        await store.loadIfNeeded(for: personalized)

        #expect(repository.categoryCalls == ["zh-Hant"])
        #expect(store.categories.map(\.id) == ["one"])
    }

    @Test
    func requiredCategoryFailureCanRetry() async {
        let repository = CatalogRepositoryFake()
        repository.categoriesHandler = { [self] _ in
            if repository.categoryCalls.count == 1 {
                throw TestFailure.boom
            }
            return CategoriesResponse(categories: [self.category("recovered")])
        }
        let store = CategoriesStore(repository: repository)
        let context = self.context(language: "zh-Hant")

        await store.loadIfNeeded(for: context)
        #expect(store.loaded)
        #expect(store.lastError != nil)

        await store.loadIfNeeded(for: context)
        #expect(repository.categoryCalls.count == 2)
        #expect(store.lastError == nil)
        #expect(store.categories.map(\.id) == ["recovered"])
    }

    private func context(
        language: String,
        userID: UUID? = nil,
        includePersonalization: Bool = false
    )
        -> CatalogContext
    {
        CatalogContext(
            contentLanguageCode: language,
            learningDirectionCode: "zh-en",
            userID: userID,
            includePersonalization: includePersonalization
        )
    }

    private func wordsResponse(_ words: [CardWord]) -> WordsListResponse {
        WordsListResponse(words: words, total: words.count)
    }

    private func word(_ id: String, label: String? = nil) -> CardWord {
        CardWord(
            id: id,
            word: label ?? id,
            chinese: "",
            imageUrl: "",
            category: "test",
            pronunciation: ""
        )
    }

    private func category(_ id: String) -> TujiCategory {
        TujiCategory(
            id: id,
            name: id,
            nameZh: id,
            emoji: "",
            description: nil,
            color: nil,
            imageUrl: nil
        )
    }
}

@MainActor
private final class AsyncResultGate<Value> {
    private var result: Result<Value, Error>?
    private var continuation: CheckedContinuation<Void, Never>?

    func wait() async throws -> Value {
        if let result = self.result {
            self.result = nil
            return try result.get()
        }
        await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
        guard let result = self.result else {
            throw TestFailure.gateMissingResult
        }
        self.result = nil
        return try result.get()
    }

    func succeed(_ value: Value) {
        self.resume(with: .success(value))
    }

    func fail(_ error: Error) {
        self.resume(with: .failure(error))
    }

    private func resume(with result: Result<Value, Error>) {
        self.result = result
        let continuation = self.continuation
        self.continuation = nil
        continuation?.resume()
    }
}

@MainActor
private final class CatalogRepositoryFake: CatalogRepository {
    var categoryCalls: [String] = []
    var wordCalls: [(lang: String, learning: String)] = []
    var customCalls: [(lang: String, learning: String)] = []
    var savedCalls: [(lang: String, learning: String)] = []

    var categoriesHandler: @MainActor (String) async throws -> CategoriesResponse = { _ in
        CategoriesResponse(categories: [])
    }

    var wordsHandler: @MainActor (String, String) async throws -> WordsListResponse = { _, _ in
        WordsListResponse(words: [], total: 0)
    }

    var customHandler: @MainActor (String, String) async throws -> WordsListResponse = { _, _ in
        WordsListResponse(words: [], total: 0)
    }

    var savedHandler: @MainActor (String, String) async throws -> WordsListResponse = { _, _ in
        WordsListResponse(words: [], total: 0)
    }

    func loadCategories(lang: String) async throws -> CategoriesResponse {
        self.categoryCalls.append(lang)
        return try await self.categoriesHandler(lang)
    }

    func loadWords(lang: String, learning: String) async throws -> WordsListResponse {
        self.wordCalls.append((lang, learning))
        return try await self.wordsHandler(lang, learning)
    }

    func loadCustomWords(lang: String, learning: String) async throws -> WordsListResponse {
        self.customCalls.append((lang, learning))
        return try await self.customHandler(lang, learning)
    }

    func loadSavedWords(lang: String, learning: String) async throws -> WordsListResponse {
        self.savedCalls.append((lang, learning))
        return try await self.savedHandler(lang, learning)
    }

    func search(_: String) async throws -> SearchResponse {
        throw TestFailure.unimplemented
    }

    func word(id _: String, lang _: String, learning _: String) async throws -> Word {
        throw TestFailure.unimplemented
    }
}

@MainActor
private func waitUntil(
    _ predicate: @MainActor () -> Bool
) async {
    for _ in 0..<1000 {
        if predicate() { return }
        await Task.yield()
    }
    Issue.record("Timed out waiting for asynchronous test state")
}

private enum TestFailure: Error {
    case boom
    case gateMissingResult
    case unimplemented
}
