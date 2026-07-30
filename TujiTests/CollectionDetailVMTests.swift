// Pins CollectionDetailVM: the preview header shows before the load, a successful
// load populates member items, and a failed load keeps the preview on screen while
// surfacing the error. Driven through a synchronous FakeCollectionDetailReading.

import Foundation
import Testing
@testable import Tuji

@MainActor
struct CollectionDetailVMTests {
    private func collection(id: String) -> AtlasCollection {
        AtlasCollection(
            id: id,
            slug: "slug-\(id)",
            title: "C\(id)",
            description: nil,
            targetLanguage: .ja,
            author: AtlasAuthorRef(handle: "u", displayName: "U", avatar: "face"),
            itemCount: 2,
            saveCount: 0,
            coverImageUrl: nil,
            publishedAt: nil
        )
    }

    private func item(id: String) -> AtlasPublicItem {
        AtlasPublicItem(
            id: id,
            slug: "slug-\(id)",
            lemma: "cat",
            displayZhHant: "貓",
            targetLanguage: .ja,
            category: nil,
            imageUrl: nil,
            author: nil,
            publishedAt: nil
        )
    }

    @Test
    func previewHeaderShowsBeforeLoad() {
        let vm = CollectionDetailVM(
            slug: "s",
            preview: self.collection(id: "a"),
            repo: FakeCollectionDetailReading()
        )
        #expect(vm.collection != nil)
        if case .loading = vm.phase {} else {
            Issue.record("expected phase == .loading, got \(vm.phase)")
        }
    }

    @Test
    func loadPopulatesItemsAndMarksReady() async {
        let fake = FakeCollectionDetailReading()
        fake.result = .success(.init(
            collection: self.collection(id: "a"),
            items: [self.item(id: "x"), self.item(id: "y")]
        ))
        let vm = CollectionDetailVM(slug: "s", repo: fake)

        await vm.load()

        #expect(vm.collection != nil)
        #expect(vm.items.count == 2)
        #expect(vm.phase == .ready)
    }

    @Test
    func failedLoadKeepsPreviewAndSurfacesError() async {
        let fake = FakeCollectionDetailReading()
        fake.result = .failure(FakeError.boom)
        let vm = CollectionDetailVM(
            slug: "s",
            preview: self.collection(id: "a"),
            repo: fake
        )

        await vm.load()

        #expect(vm.collection != nil) // preview kept on screen
        #expect(vm.items.isEmpty)
        #expect(vm.errorMessage != nil)
    }

    @Test
    func unavailableCollectionClearsAStalePreview() async {
        let fake = FakeCollectionDetailReading()
        fake.result = .failure(APIError.notFound)
        let vm = CollectionDetailVM(
            slug: "s",
            preview: self.collection(id: "a"),
            repo: fake
        )

        await vm.load()

        #expect(vm.collection == nil)
        #expect(vm.isUnavailable)
    }

    @Test
    func bookmarkState404DoesNotEraseSuccessfullyLoadedCollection() async {
        let details = FakeCollectionDetailReading()
        let bookmarks = FakeDetailBookmarking()
        bookmarks.stateResult = .failure(APIError.notFound)
        let vm = CollectionDetailVM(
            slug: "s",
            preview: self.collection(id: "a"),
            repo: details,
            bookmarkRepo: bookmarks
        )

        await vm.load()
        await vm.loadBookmarkState()

        #expect(vm.collection != nil)
        #expect(!vm.isUnavailable)
        #expect(vm.bookmarkLoaded)
        #expect(vm.bookmarkError != nil)
    }

    @Test
    func saveStateAndCountChangeOnlyAfterServerSuccess() async {
        let details = FakeCollectionDetailReading()
        let bookmarks = FakeDetailBookmarking()
        bookmarks.saveResult = .failure(FakeError.boom)
        let vm = CollectionDetailVM(
            slug: "s",
            preview: self.collection(id: "a"),
            repo: details,
            bookmarkRepo: bookmarks
        )

        let failed = await vm.save()
        #expect(failed == nil)
        #expect(!vm.isSaved)
        #expect(vm.collection?.saveCount == 0)
        #expect(vm.bookmarkActionError != nil)

        vm.dismissBookmarkActionError()
        #expect(vm.bookmarkActionError == nil)

        bookmarks.saveResult = .success(.init(ok: true, saved: true, saveCount: 7))
        let saved = await vm.save()
        #expect(saved?.saveCount == 7)
        #expect(vm.isSaved)
        #expect(vm.bookmarkLoaded)
    }
}

// MARK: - Fake

private enum FakeError: Error {
    case boom
}

@MainActor
private final class FakeCollectionDetailReading: CollectionDetailReading {
    var result: Result<AtlasCollectionDetailResponse, Error> = .success(
        .init(
            collection: AtlasCollection(
                id: "a",
                slug: "s",
                title: "C",
                description: nil,
                targetLanguage: .ja,
                author: AtlasAuthorRef(handle: "u", displayName: "U", avatar: "face"),
                itemCount: 0,
                saveCount: 0,
                coverImageUrl: nil,
                publishedAt: nil
            ),
            items: []
        )
    )

    func collection(slug _: String) async throws -> AtlasCollectionDetailResponse {
        try self.result.get()
    }
}

@MainActor
private final class FakeDetailBookmarking: CollectionBookmarking {
    var stateResult: Result<AtlasSaveResponse, Error> = .success(
        .init(ok: true, saved: false, saveCount: 0)
    )
    var saveResult: Result<AtlasSaveResponse, Error> = .success(
        .init(ok: true, saved: true, saveCount: 1)
    )

    func savedCollections(lang _: TargetLanguage) async throws -> [AtlasCollection] {
        []
    }

    func collectionSaveState(slug _: String) async throws -> AtlasSaveResponse {
        try self.stateResult.get()
    }

    func saveCollection(slug _: String) async throws -> AtlasSaveResponse {
        try self.saveResult.get()
    }

    func unsaveCollection(slug _: String) async throws -> AtlasSaveResponse {
        .init(ok: true, saved: false, saveCount: 0)
    }
}
