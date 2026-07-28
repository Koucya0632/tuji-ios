// Pins AuthorProfileVM: a successful load populates the author + their items and
// marks ready; a failed load clears both and surfaces the error. Driven through a
// synchronous FakeAuthorReading.

import Foundation
import Testing
@testable import Tuji

@MainActor
struct AuthorProfileVMTests {
    private func author(handle: String = "mika_k") -> AtlasAuthor {
        AtlasAuthor(
            handle: handle,
            displayName: "Mika",
            avatar: "face",
            joinedAt: "2026-01",
            publishedCount: 4,
            saveCount: 12
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
    func loadPopulatesAuthorAndItemsAndMarksReady() async {
        let fake = FakeAuthorReading()
        fake.result = .success(.init(author: self.author(), items: [self.item(id: "x")]))
        let vm = AuthorProfileVM(handle: "mika_k", repo: fake)

        await vm.load()

        #expect(vm.author != nil)
        #expect(vm.items.count == 1)
        #expect(vm.phase == .ready)
    }

    @Test
    func failedLoadClearsAndSurfacesError() async {
        let fake = FakeAuthorReading()
        fake.result = .success(.init(author: self.author(), items: [self.item(id: "x")]))
        let vm = AuthorProfileVM(handle: "mika_k", repo: fake)
        await vm.load() // first a good load…

        fake.result = .failure(FakeError.boom)
        await vm.load() // …then a failure clears it

        #expect(vm.author == nil)
        #expect(vm.items.isEmpty)
        #expect(vm.errorMessage != nil)
    }
}

// MARK: - Fake

private enum FakeError: Error {
    case boom
}

@MainActor
private final class FakeAuthorReading: AuthorReading {
    var result: Result<AtlasAuthorResponse, Error> = .success(
        .init(
            author: AtlasAuthor(
                handle: "u",
                displayName: "U",
                avatar: "face",
                joinedAt: nil,
                publishedCount: 0,
                saveCount: 0
            ),
            items: []
        )
    )

    func author(handle _: String) async throws -> AtlasAuthorResponse {
        try self.result.get()
    }
}
