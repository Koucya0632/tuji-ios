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
