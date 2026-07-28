// Pins MyCollectionsVM's load state machine behind the CollectionManaging seam:
// a successful load populates + clears loading, a failure surfaces the error and
// still clears loading (so the screen doesn't hang on a spinner).

import Foundation
import Testing
@testable import Tuji

@MainActor
struct MyCollectionsVMTests {
    private func collection(id: String) -> AtlasMyCollection {
        AtlasMyCollection(
            id: id,
            slug: "slug-\(id)",
            title: "T\(id)",
            description: nil,
            targetLanguage: .ja,
            reviewStatus: "draft",
            itemCount: 0,
            coverImageUrl: nil,
            publishedAt: nil,
            updatedAt: nil
        )
    }

    @Test
    func loadPopulatesAndClearsLoading() async {
        let fake = FakeCollectionManaging()
        fake.myResult = .success([self.collection(id: "a"), self.collection(id: "b")])
        let vm = MyCollectionsVM(repo: fake)

        await vm.load()

        #expect(vm.collections.count == 2)
        #expect(!vm.loading)
        #expect(vm.loadError == nil)
    }

    @Test
    func loadFailureSetsErrorAndClearsLoading() async {
        let fake = FakeCollectionManaging()
        fake.myResult = .failure(FakeError.boom)
        let vm = MyCollectionsVM(repo: fake)

        await vm.load()

        #expect(vm.collections.isEmpty)
        #expect(vm.loadError != nil)
        #expect(!vm.loading)
    }
}

private enum FakeError: Error { case boom }

@MainActor
private final class FakeCollectionManaging: CollectionManaging {
    var myResult: Result<[AtlasMyCollection], Error> = .success([])

    struct NotImplemented: Error {}

    func myCollections() async throws -> [AtlasMyCollection] {
        try self.myResult.get()
    }

    func createCollection(title _: String, description _: String?, targetLanguage _: TargetLanguage) async throws
        -> AtlasMyCollection
    {
        throw NotImplemented()
    }

    func collectionCandidates(lang _: TargetLanguage) async throws -> [AtlasPublicItem] {
        []
    }
}
