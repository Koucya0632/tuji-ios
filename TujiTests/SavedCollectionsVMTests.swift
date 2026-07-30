import Foundation
import Testing
@testable import Tuji

@MainActor
struct SavedCollectionsVMTests {
    @Test
    func firstLoadUsesCurrentLanguageAndPreservesServerOrder() async {
        let fake = FakeCollectionBookmarking()
        fake.saved = [self.collection("new"), self.collection("old")]
        let vm = SavedCollectionsVM(repo: fake)

        await vm.load(lang: .ja)

        #expect(fake.requestedLanguages == [.ja])
        #expect(vm.collections.map(\.id) == ["new", "old"])
        #expect(vm.phase == .ready)
    }

    @Test
    func sameLanguageDoesNotReloadUntilForced() async {
        let fake = FakeCollectionBookmarking()
        let vm = SavedCollectionsVM(repo: fake)

        await vm.load(lang: .ja)
        await vm.load(lang: .ja)
        #expect(fake.requestedLanguages.count == 1)

        await vm.load(lang: .ja, force: true)
        #expect(fake.requestedLanguages.count == 2)
    }

    @Test
    func confirmedBookmarkChangeInsertsOrRemovesImmediately() {
        let vm = SavedCollectionsVM(repo: FakeCollectionBookmarking())
        let collection = self.collection("a")

        vm.apply(.init(collection: collection, saved: true), lang: .ja)
        #expect(vm.collections == [collection])

        vm.apply(.init(collection: collection, saved: false), lang: .ja)
        #expect(vm.collections.isEmpty)
    }

    private func collection(_ id: String) -> AtlasCollection {
        AtlasCollection(
            id: id,
            slug: "slug-\(id)",
            title: id,
            description: nil,
            targetLanguage: .ja,
            author: AtlasAuthorRef(handle: "other", displayName: "Other", avatar: "face"),
            itemCount: 1,
            saveCount: 0,
            coverImageUrl: nil,
            publishedAt: nil
        )
    }
}

@MainActor
private final class FakeCollectionBookmarking: CollectionBookmarking {
    var saved: [AtlasCollection] = []
    var requestedLanguages: [TargetLanguage] = []
    var state = AtlasSaveResponse(ok: true, saved: false, saveCount: 0)
    var saveResult: Result<AtlasSaveResponse, Error> = .success(
        AtlasSaveResponse(ok: true, saved: true, saveCount: 1)
    )
    var unsaveResult: Result<AtlasSaveResponse, Error> = .success(
        AtlasSaveResponse(ok: true, saved: false, saveCount: 0)
    )

    func savedCollections(lang: TargetLanguage) async throws -> [AtlasCollection] {
        self.requestedLanguages.append(lang)
        return self.saved
    }

    func collectionSaveState(slug _: String) async throws -> AtlasSaveResponse {
        self.state
    }

    func saveCollection(slug _: String) async throws -> AtlasSaveResponse {
        try self.saveResult.get()
    }

    func unsaveCollection(slug _: String) async throws -> AtlasSaveResponse {
        try self.unsaveResult.get()
    }
}
