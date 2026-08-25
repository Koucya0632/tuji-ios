// Pins MyCollectionsVM's load state machine behind the CollectionManaging seam:
// a successful load populates + clears loading, a failure surfaces the error and
// still clears loading (so the screen doesn't hang on a spinner).

import Foundation
import Testing
@testable import Tuji

@MainActor
struct MyCollectionsVMTests {
    private func collection(
        id: String,
        language: TargetLanguage = .ja,
        review: AtlasReviewStatus = .draft
    )
        -> AtlasMyCollection
    {
        AtlasMyCollection(
            id: id,
            slug: "slug-\(id)",
            title: "T\(id)",
            description: nil,
            targetLanguage: language,
            reviewStatus: review.rawValue,
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

    // MARK: - Delete

    @Test
    func deleteRemovesCollectionAfterServerSuccess() async {
        let fake = FakeCollectionManaging()
        fake.myResult = .success([self.collection(id: "a"), self.collection(id: "b")])
        let vm = MyCollectionsVM(repo: fake, cache: MyCollectionsCache())
        await vm.load()
        let target = vm.collections[0]

        await vm.delete(target, refreshing: SpyAtlasMutationRefreshing())

        #expect(fake.deletedIds == ["a"])
        #expect(vm.collections.map(\.id) == ["b"])
        #expect(vm.deleteError == nil)
        #expect(!vm.deleting)
    }

    /// A row that vanishes from the list on a failed delete is a lie the next
    /// refresh silently corrects. The cache is only touched once the server agrees.
    @Test
    func deleteFailureKeepsTheRowAndSurfacesTheError() async {
        let fake = FakeCollectionManaging()
        fake.myResult = .success([self.collection(id: "a")])
        fake.deleteError = FakeError.boom
        let vm = MyCollectionsVM(repo: fake, cache: MyCollectionsCache())
        await vm.load()
        let target = vm.collections[0]

        await vm.delete(target, refreshing: SpyAtlasMutationRefreshing())

        #expect(vm.collections.map(\.id) == ["a"])
        #expect(vm.deleteError != nil)
        #expect(!vm.deleting)
    }

    /// A failed delete must not report a mutation: 物見's feed would drop its
    /// cache and re-fetch to discover nothing had changed.
    @Test
    func aFailedDeleteRefreshesNothing() async {
        let fake = FakeCollectionManaging()
        fake.myResult = .success([self.collection(id: "a", review: .approved)])
        fake.deleteError = FakeError.boom
        let vm = MyCollectionsVM(repo: fake, cache: MyCollectionsCache())
        await vm.load()
        let spy = SpyAtlasMutationRefreshing()

        await vm.delete(vm.collections[0], refreshing: spy)

        #expect(spy.reported.isEmpty)
    }

    /// `wasPublic` is a property of the row, not something the caller re-derives
    /// — it decides whether 物見's feed is invalidated. The `View` used to spell
    /// it inline, three lines from the warning copy making the same distinction.
    @Test
    func deletingAnApprovedCollectionReportsItAsPublic() async {
        let fake = FakeCollectionManaging()
        fake.myResult = .success([self.collection(id: "a", review: .approved)])
        let vm = MyCollectionsVM(repo: fake, cache: MyCollectionsCache())
        await vm.load()
        let spy = SpyAtlasMutationRefreshing()

        await vm.delete(vm.collections[0], refreshing: spy)

        #expect(spy.reported == [.collectionDeleted(wasPublic: true)])
    }

    @Test
    func deletingADraftCollectionReportsItAsPrivate() async {
        let fake = FakeCollectionManaging()
        fake.myResult = .success([self.collection(id: "a", review: .draft)])
        let vm = MyCollectionsVM(repo: fake, cache: MyCollectionsCache())
        await vm.load()
        let spy = SpyAtlasMutationRefreshing()

        await vm.delete(vm.collections[0], refreshing: spy)

        #expect(spy.reported == [.collectionDeleted(wasPublic: false)])
    }

    /// The swipe row and the prompt can both be live for a moment. A second
    /// delete arriving mid-flight must not issue a second request.
    @Test
    func aSecondDeleteMidFlightIsIgnored() async {
        let fake = FakeCollectionManaging()
        fake.myResult = .success([self.collection(id: "a")])
        let vm = MyCollectionsVM(repo: fake, cache: MyCollectionsCache())
        await vm.load()
        let target = vm.collections[0]

        fake.onDelete = { @MainActor in
            // Re-entrant call while the first is still awaiting the server.
            await vm.delete(target, refreshing: SpyAtlasMutationRefreshing())
        }
        await vm.delete(target, refreshing: SpyAtlasMutationRefreshing())

        #expect(fake.deletedIds == ["a"])
    }

    // MARK: - Delete warning

    /// Three different promises to the author, and the one that matters is
    /// `approved`: it is the only one that takes something down for other
    /// people. It lived in a `private func` on the `View`.
    @Test
    func theWarningTellsApartReviewPublicAndPrivate() {
        let vm = MyCollectionsVM(repo: FakeCollectionManaging(), cache: MyCollectionsCache())

        #expect(vm.deleteWarning(for: self.collection(id: "a", review: .approved)) == .takesDownFromPublic)

        for pending in [AtlasReviewStatus.pending, .pendingAuto, .pendingReview] {
            #expect(vm.deleteWarning(for: self.collection(id: "a", review: pending)) == .cancelsReview)
        }

        for quiet in [AtlasReviewStatus.draft, .rejected, .takedown, .withdrawn] {
            #expect(vm.deleteWarning(for: self.collection(id: "a", review: quiet)) == .privateOnly)
        }
    }

    /// 已收回 is the author's own withdrawal — reversible, no penalty, and not
    /// public any more. Warning them about a takedown that already happened
    /// would misdescribe what the button does.
    @Test
    func aWithdrawnCollectionIsNotWarnedAboutAsPublic() {
        let vm = MyCollectionsVM(repo: FakeCollectionManaging(), cache: MyCollectionsCache())
        #expect(vm.deleteWarning(for: self.collection(id: "a", review: .withdrawn)) == .privateOnly)
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
    /// Runs while a delete is in flight, so a test can re-enter the VM the way
    /// a second tap on the swipe row would.
    var onDelete: (@MainActor () async -> Void)?

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
        await self.onDelete?()
        if let deleteError {
            throw deleteError
        }
        self.deletedIds.append(id)
    }

    func collectionCandidates(lang _: TargetLanguage) async throws -> [AtlasPublicItem] {
        []
    }
}
