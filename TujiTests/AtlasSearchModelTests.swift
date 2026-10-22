// Pins 物見搜尋's model: the debounce collapses typing into one request, a
// stale answer never replaces a newer query, clearing the field goes back to
// idle, a failure is shown, long input is trimmed to what the backend accepts,
// and blocked authors are hidden without a refetch.

import Foundation
import Testing
@testable import Tuji

@MainActor
private final class StubSearch: AtlasPublicSearching {
    var calls: [(q: String, lang: TargetLanguage)] = []
    var response = AtlasPublicSearchResponse(collections: [], items: [])
    var error: Error?

    func searchPublic(q: String, lang: TargetLanguage) async throws -> AtlasPublicSearchResponse {
        self.calls.append((q, lang))
        if let error { throw error }
        return self.response
    }
}

private struct Boom: Error {}

@MainActor
struct AtlasSearchModelTests {
    private func model(_ repo: StubSearch) -> AtlasSearchModel {
        AtlasSearchModel(repository: repo, debounce: .zero, sleep: { _ in await Task.yield() })
    }

    private func collection(_ id: String, author: String = "other") -> AtlasCollection {
        AtlasCollection(
            id: id,
            slug: "slug-\(id)",
            title: id,
            description: nil,
            targetLanguage: .ja,
            author: AtlasAuthorRef(handle: author, displayName: author, avatar: "face"),
            itemCount: 1,
            saveCount: 0,
            avatarColor: nil,
            avatarImageUrl: nil,
            coverImageUrl: nil,
            publishedAt: nil
        )
    }

    private func item(_ id: String, author: String = "other") -> AtlasPublicItem {
        AtlasPublicItem(
            id: id,
            slug: "s-\(id)",
            lemma: "猫",
            displayZhHant: "貓",
            targetLanguage: .ja,
            category: nil,
            imageUrl: nil,
            author: AtlasAuthorRef(handle: author, displayName: author, avatar: "face"),
            publishedAt: nil
        )
    }

    @Test
    func typingSearchesOnceForTheLastQueryInTheLearningLanguage() async {
        let repo = StubSearch()
        repo.response = AtlasPublicSearchResponse(collections: [self.collection("c1")], items: [self.item("i1")])
        let model = self.model(repo)

        model.updateQuery("貓", language: .ja)
        model.updateQuery("貓咪", language: .ja)
        await model.settle()

        #expect(repo.calls.map(\.q) == ["貓咪"])
        #expect(repo.calls.map(\.lang) == [.ja])
        #expect(model.phase == .ready)
        #expect(model.lastQuery == "貓咪")
        #expect(model.collections.map(\.id) == ["c1"])
        #expect(model.items.map(\.id) == ["i1"])
    }

    @Test
    func clearingTheFieldReturnsToIdleAndDropsResults() async {
        let repo = StubSearch()
        repo.response = AtlasPublicSearchResponse(collections: [self.collection("c1")], items: [])
        let model = self.model(repo)

        model.updateQuery("cat", language: .en)
        await model.settle()
        model.updateQuery("   ", language: .en)

        #expect(model.phase == .idle)
        #expect(model.isEmpty)
        #expect(model.lastQuery.isEmpty)
    }

    @Test
    func aFailureIsShownAndRetryRunsTheSameQuery() async {
        let repo = StubSearch()
        repo.error = Boom()
        let model = self.model(repo)

        model.updateQuery("kettle", language: .en)
        await model.settle()
        guard case .failed = model.phase else {
            Issue.record("expected .failed, got \(model.phase)")
            return
        }

        repo.error = nil
        model.retry(language: .en)
        await model.settle()

        #expect(repo.calls.map(\.q) == ["kettle", "kettle"])
        #expect(model.phase == .ready)
    }

    @Test
    func longInputIsTrimmedToTheBackendCap() async {
        let repo = StubSearch()
        let model = self.model(repo)

        model.updateQuery("  " + String(repeating: "a", count: 60) + "  ", language: .en)
        await model.settle()

        #expect(repo.calls.first?.q.count == 40)
    }

    @Test
    func blockedAuthorsAreHiddenWithoutARefetch() async {
        let repo = StubSearch()
        repo.response = AtlasPublicSearchResponse(
            collections: [self.collection("c1", author: "spam"), self.collection("c2")],
            items: [self.item("i1", author: "Spam"), self.item("i2")]
        )
        let model = self.model(repo)
        model.updateQuery("x", language: .ja)
        await model.settle()

        model.applyBlocks(["spam"])
        #expect(model.collections.map(\.id) == ["c2"])
        #expect(model.items.map(\.id) == ["i2"])

        model.applyBlocks([])
        #expect(model.collections.map(\.id) == ["c1", "c2"])
        #expect(repo.calls.count == 1)
    }
}
