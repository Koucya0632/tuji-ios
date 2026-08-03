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

    @Test
    func filtersCollectionsByCurrentLanguage() async {
        let fake = FakeCollectionManaging()
        fake.myResult = .success([
            self.collection(id: "ja", language: .ja),
            self.collection(id: "en", language: .en)
        ])
        let vm = MyCollectionsVM(repo: fake)

        await vm.load()

        #expect(vm.collections(for: .ja).map(\.id) == ["ja"])
        #expect(vm.collections(for: .en).map(\.id) == ["en"])
    }

    @Test
    func prependPlacesNewCollectionFirstWithoutDuplicates() async {
        let fake = FakeCollectionManaging()
        fake.myResult = .success([self.collection(id: "a"), self.collection(id: "b")])
        let vm = MyCollectionsVM(repo: fake)
        await vm.load()

        vm.prepend(self.collection(id: "b"))

        #expect(vm.collections.map(\.id) == ["b", "a"])
    }

    @Test
    func deleteRemovesCollectionAfterServerSuccess() async throws {
        let fake = FakeCollectionManaging()
        fake.myResult = .success([self.collection(id: "a"), self.collection(id: "b")])
        let vm = MyCollectionsVM(repo: fake)
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
        let vm = MyCollectionsVM(repo: fake)
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

    struct NotImplemented: Error {}

    func myCollections() async throws -> [AtlasMyCollection] {
        try self.myResult.get()
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
