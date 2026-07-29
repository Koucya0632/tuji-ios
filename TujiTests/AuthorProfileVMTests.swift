// Pins AuthorProfileVM: a successful load populates the author + their items and
// marks ready; a failed load clears both and surfaces the error. The 404 case is
// pinned separately because it is NOT a failure — the endpoint 404s for a real
// account with nothing approved yet, and the self-view has to be able to tell
// "you haven't published anything" apart from "no such author". Language
// grouping is pinned here too: it decides what the profile actually renders.
//
// Driven through a synchronous FakeAuthorReading.

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
            bio: nil,
            joinedAt: "2026-01",
            publishedCount: 4,
            saveCount: 12
        )
    }

    private func collection(id: String, language: TargetLanguage = .ja) -> AtlasCollection {
        AtlasCollection(
            id: id,
            slug: "c-\(id)",
            title: "廚房裡的日文",
            description: nil,
            targetLanguage: language,
            author: nil,
            itemCount: 8,
            saveCount: 3,
            coverImageUrl: nil,
            publishedAt: nil
        )
    }

    private func item(id: String, language: TargetLanguage = .ja) -> AtlasPublicItem {
        AtlasPublicItem(
            id: id,
            slug: "slug-\(id)",
            lemma: "cat",
            displayZhHant: "貓",
            targetLanguage: language,
            category: nil,
            imageUrl: nil,
            author: nil,
            publishedAt: nil
        )
    }

    // MARK: - Load

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
        #expect(vm.groups.isEmpty)
        #expect(vm.errorMessage != nil)
    }

    // MARK: - notFound is not a failure

    /// The one distinction the self-view is built on: 404 means "nothing
    /// approved yet", which is the normal state of a new author, so it must not
    /// arrive as an error with a retry button.
    @Test
    func notFoundLandsInItsOwnPhaseWithNoErrorMessage() async {
        let fake = FakeAuthorReading()
        fake.result = .failure(APIError.notFound)
        let vm = AuthorProfileVM(handle: "mika_k", isSelf: true, repo: fake)

        await vm.load()

        #expect(vm.phase == .notFound)
        #expect(vm.errorMessage == nil)
        #expect(vm.author == nil)
    }

    @Test
    func nonNotFoundErrorsStillFail() async {
        let fake = FakeAuthorReading()
        fake.result = .failure(APIError.server(status: 500, body: nil))
        let vm = AuthorProfileVM(handle: "mika_k", repo: fake)

        await vm.load()

        #expect(vm.phase != .notFound)
        #expect(vm.errorMessage != nil)
    }

    // MARK: - Self-view reads past the caches

    /// A self-view exists to answer "did my edit land?", so it must never be
    /// served the CDN's 30-minute-old copy.
    @Test
    func selfViewForcesAReload() async {
        let fake = FakeAuthorReading()
        let vm = AuthorProfileVM(handle: "mika_k", isSelf: true, repo: fake)

        await vm.load()

        #expect(fake.lastForceReload == true)
    }

    @Test
    func visitorViewKeepsTheCache() async {
        let fake = FakeAuthorReading()
        let vm = AuthorProfileVM(handle: "mika_k", repo: fake)

        await vm.load()

        #expect(fake.lastForceReload == false)
    }

    // MARK: - Language grouping

    /// Nothing is filtered out — a profile is a body of work, not a study feed —
    /// so every item survives grouping and the counts add back up to the total.
    @Test
    func groupsSplitByLanguageWithoutDroppingItems() async {
        let fake = FakeAuthorReading()
        fake.result = .success(.init(
            author: self.author(),
            items: [
                self.item(id: "a", language: .ja),
                self.item(id: "b", language: .en),
                self.item(id: "c", language: .ja)
            ]
        ))
        let vm = AuthorProfileVM(handle: "mika_k", repo: fake)

        await vm.load()

        #expect(vm.groups.count == 2)
        #expect(vm.groups.map(\.count).reduce(0, +) == vm.items.count)
        #expect(vm.groups.first { $0.language == .ja }?.count == 2)
        #expect(vm.groups.first { $0.language == .en }?.count == 1)
    }

    /// Server order is newest-first, so first-appearance ordering puts the
    /// language the author is currently working in at the top — and it has to be
    /// stable, or the page reshuffles between loads.
    @Test
    func groupOrderFollowsFirstAppearance() async {
        let fake = FakeAuthorReading()
        fake.result = .success(.init(
            author: self.author(),
            items: [
                self.item(id: "a", language: .en),
                self.item(id: "b", language: .ja)
            ]
        ))
        let vm = AuthorProfileVM(handle: "mika_k", repo: fake)

        await vm.load()

        #expect(vm.groups.map(\.language) == [.en, .ja])
    }

    // MARK: - Segments

    /// Most authors have none. A segmented control that advertises an empty room
    /// is worse than no control, so it isn't drawn at all.
    @Test
    func noCollectionsMeansNoSegmentedControl() async {
        let fake = FakeAuthorReading()
        fake.result = .success(.init(
            author: self.author(),
            items: [self.item(id: "a")],
            collections: []
        ))
        let vm = AuthorProfileVM(handle: "mika_k", repo: fake)

        await vm.load()

        #expect(vm.showsSegmentedControl == false)
        #expect(vm.visibleSegment == .items)
    }

    /// Curated work is the stronger signal, so it leads when it exists.
    @Test
    func collectionsLeadWhenTheyExist() async {
        let fake = FakeAuthorReading()
        fake.result = .success(.init(
            author: self.author(),
            items: [self.item(id: "a")],
            collections: [self.collection(id: "c1")]
        ))
        let vm = AuthorProfileVM(handle: "mika_k", repo: fake)

        await vm.load()

        #expect(vm.showsSegmentedControl)
        #expect(vm.visibleSegment == .collections)
        #expect(vm.collections.count == 1)
    }

    /// The user's choice is honoured while the control is on screen.
    @Test
    func switchingToItemsIsRespected() async {
        let fake = FakeAuthorReading()
        fake.result = .success(.init(
            author: self.author(),
            items: [self.item(id: "a")],
            collections: [self.collection(id: "c1")]
        ))
        let vm = AuthorProfileVM(handle: "mika_k", repo: fake)
        await vm.load()

        vm.segment = .items

        #expect(vm.visibleSegment == .items)
    }

    /// The trap this guards: a reload that drops the author's last collection
    /// (withdrawn, or unpublished) must not strand the page on a 合集 tab that
    /// no longer has a control to switch away from.
    @Test
    func losingTheLastCollectionFallsBackToItems() async {
        let fake = FakeAuthorReading()
        fake.result = .success(.init(
            author: self.author(),
            items: [self.item(id: "a")],
            collections: [self.collection(id: "c1")]
        ))
        let vm = AuthorProfileVM(handle: "mika_k", repo: fake)
        await vm.load()
        #expect(vm.visibleSegment == .collections)

        fake.result = .success(.init(
            author: self.author(),
            items: [self.item(id: "a")],
            collections: []
        ))
        await vm.load()

        #expect(vm.showsSegmentedControl == false)
        #expect(vm.visibleSegment == .items)
    }

    /// The key was added after 1.0.4 shipped, so a build carrying it can meet a
    /// server that predates it. That must decode, not throw.
    @Test
    func aPayloadWithoutCollectionsStillDecodes() throws {
        let json = Data("""
        {"author":{"handle":"mika_k","displayName":"Mika","avatar":"face",
        "joinedAt":null,"publishedCount":1,"saveCount":0},
        "items":[]}
        """.utf8)

        let decoded = try JSONDecoder().decode(AtlasAuthorResponse.self, from: json)

        #expect(decoded.collections.isEmpty)
        #expect(decoded.author.handle == "mika_k")
    }

    @Test
    func oneLanguageProducesOneGroup() async {
        let fake = FakeAuthorReading()
        fake.result = .success(.init(
            author: self.author(),
            items: [self.item(id: "a"), self.item(id: "b")]
        ))
        let vm = AuthorProfileVM(handle: "mika_k", repo: fake)

        await vm.load()

        #expect(vm.groups.count == 1)
        #expect(vm.groups.first?.count == 2)
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
                bio: nil,
                joinedAt: nil,
                publishedCount: 0,
                saveCount: 0
            ),
            items: []
        )
    )

    private(set) var lastForceReload: Bool?

    func author(handle _: String, forceReload: Bool) async throws -> AtlasAuthorResponse {
        self.lastForceReload = forceReload
        return try self.result.get()
    }
}
