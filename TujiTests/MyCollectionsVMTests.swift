// Pins MyCollectionsVM's load state machine behind the CollectionManaging seam:
// a successful load populates + clears loading, a failure surfaces the error and
// still clears loading (so the screen doesn't hang on a spinner).

import Foundation
import Testing
@testable import Tuji

@MainActor
struct MyCollectionsVMTests {
    private func collection(id: String, language: TargetLanguage = .ja) -> AtlasMyCollection {
        AtlasMyCollection(
            id: id,
            slug: "slug-\(id)",
            title: "T\(id)",
            description: nil,
            targetLanguage: language,
            reviewStatus: "draft",
            itemCount: 0,
            avatarColor: nil,
            avatarImageUrl: nil,
            coverImageUrl: nil,
            publishedAt: nil,
            updatedAt: nil
        )
    }

    @Test
    func loadPopulatesAndClearsLoading() async {
        let fake = FakeCollectionManaging()
        fake.myResult = .success([self.collection(id: "a"), self.collection(id: "b")])
        let vm = MyCollectionsVM(repo: fake, cache: MyCollectionsCache())

        await vm.load()

        #expect(vm.collections.count == 2)
        #expect(!vm.loading)
        #expect(vm.loadError == nil)
    }

    @Test
    func loadFailureSetsErrorAndClearsLoading() async {
        let fake = FakeCollectionManaging()
        fake.myResult = .failure(FakeError.boom)
        let vm = MyCollectionsVM(repo: fake, cache: MyCollectionsCache())

        await vm.load()

        #expect(vm.collections.isEmpty)
        #expect(vm.loadError != nil)
        #expect(!vm.loading)
    }

    /// 返回 from 編輯合集 fires the list's `.task` *and* the edit screen's
    /// `onDisappear` reload in the same frame. Two requests meant the spinner
    /// flashed twice; the second call now rides along with the first.
    @Test
    func concurrentLoadsCoalesceIntoOneRequest() async {
        let fake = FakeCollectionManaging()
        fake.myResult = .success([self.collection(id: "a")])
        let vm = MyCollectionsVM(repo: fake, cache: MyCollectionsCache())

        async let first: Void = vm.load()
        async let second: Void = vm.load()
        _ = await (first, second)

        #expect(fake.myCallCount == 1)
        #expect(vm.collections.map(\.id) == ["a"])
    }

    /// A refresh with rows already on screen must not swap them for a spinner.
    @Test
    func placeholderOnlyShowsBeforeTheFirstRowsArrive() async {
        let fake = FakeCollectionManaging()
        fake.myResult = .success([self.collection(id: "a")])
        let vm = MyCollectionsVM(repo: fake, cache: MyCollectionsCache())
        #expect(vm.showsPlaceholder)

        await vm.load()
        #expect(!vm.showsPlaceholder)

        fake.onMyCollections = { #expect(!vm.showsPlaceholder) }
        await vm.load()
    }

    /// Leaving 圖鑑管理 and coming back builds a brand-new VM on a brand-new
    /// view. The rows live in the cache, not the VM, so the return visit paints
    /// the last known 合集 immediately and refreshes behind them — no spinner.
    @Test
    func returnVisitRendersCachedRowsWithoutASpinner() async {
        let cache = MyCollectionsCache()
        let fake = FakeCollectionManaging()
        fake.myResult = .success([self.collection(id: "a")])
        await MyCollectionsVM(repo: fake, cache: cache).load()

        let onReturn = MyCollectionsVM(repo: fake, cache: cache)

        #expect(!onReturn.showsPlaceholder)
        #expect(onReturn.collections.map(\.id) == ["a"])
    }

    /// The cache outlives the session, so sign-out has to wipe it or the next
    /// account opens 合集 on the previous account's list.
    @Test
    func resetClearsRowsForTheNextAccount() async {
        let cache = MyCollectionsCache()
        let fake = FakeCollectionManaging()
        fake.myResult = .success([self.collection(id: "a")])
        await MyCollectionsVM(repo: fake, cache: cache).load()

        cache.reset()

        #expect(MyCollectionsVM(repo: fake, cache: cache).collections.isEmpty)
    }

    @Test
    func filtersCollectionsByCurrentLanguage() async {
        let fake = FakeCollectionManaging()
        fake.myResult = .success([
            self.collection(id: "ja", language: .ja),
            self.collection(id: "en", language: .en)
        ])
        let vm = MyCollectionsVM(repo: fake, cache: MyCollectionsCache())

        await vm.load()

        #expect(vm.collections(for: .ja).map(\.id) == ["ja"])
        #expect(vm.collections(for: .en).map(\.id) == ["en"])
    }

    @Test
    func prependPlacesNewCollectionFirstWithoutDuplicates() async {
        let fake = FakeCollectionManaging()
        fake.myResult = .success([self.collection(id: "a"), self.collection(id: "b")])
        let vm = MyCollectionsVM(repo: fake, cache: MyCollectionsCache())
        await vm.load()

        vm.prepend(self.collection(id: "b"))

        #expect(vm.collections.map(\.id) == ["b", "a"])
    }

    @Test
    func deleteRemovesCollectionAfterServerSuccess() async throws {
        let fake = FakeCollectionManaging()
        fake.myResult = .success([self.collection(id: "a"), self.collection(id: "b")])
        let vm = MyCollectionsVM(repo: fake, cache: MyCollectionsCache())
        await vm.load()

        try await vm.delete(id: "a")

        #expect(fake.deletedIds == ["a"])
        #expect(vm.collections.map(\.id) == ["b"])
    }

    @Test
    func deleteFailureKeepsCollection() async {
        let fake = FakeCollectionManaging()
        fake.myResult = .success([self.collection(id: "a")])
        fake.deleteError = FakeError.boom
        let vm = MyCollectionsVM(repo: fake, cache: MyCollectionsCache())
        await vm.load()

        do {
            try await vm.delete(id: "a")
            Issue.record("Expected delete to throw")
        } catch {}

        #expect(vm.collections.map(\.id) == ["a"])
    }
}

private enum FakeError: Error { case boom }

@MainActor
private final class FakeCollectionManaging: CollectionManaging {
    var myResult: Result<[AtlasMyCollection], Error> = .success([])
    var deleteError: Error?
    var deletedIds: [String] = []
    var myCallCount = 0
    /// Runs while the load is in flight, so a test can assert on mid-load state.
    var onMyCollections: (() -> Void)?

    struct NotImplemented: Error {}

    func myCollections() async throws -> [AtlasMyCollection] {
        self.myCallCount += 1
        self.onMyCollections?()
        await Task.yield()
        return try self.myResult.get()
    }

    func createCollection(title _: String, description _: String?, targetLanguage _: TargetLanguage) async throws
        -> AtlasMyCollection
    {
        throw NotImplemented()
    }

    func deleteCollection(id: String) async throws {
        if let deleteError {
            throw deleteError
        }
        self.deletedIds.append(id)
    }

    func collectionCandidates(lang _: TargetLanguage) async throws -> [AtlasPublicItem] {
        []
    }
}
