// Pins the two 合集 authoring surfaces that used to hold their own repository
// and their own state machine inside a `private struct` View: 建立合集's
// validation (which shipped an untrimmed description) and 加入項目's eligibility
// filter (which did not exist) plus its optimistic add (which never rolled back).

import Foundation
import Testing
@testable import Tuji

@MainActor
struct CollectionCreateModelTests {
    @Test
    func aBlankTitleBlocksCreationAndNeverReachesTheServer() async {
        let fake = FakeCollectionManaging()
        let model = CollectionCreateModel(language: .ja, repo: fake)
        model.title = "   "

        #expect(!model.canCreate)
        let created = await model.create()

        #expect(created == nil)
        #expect(fake.createdPayloads.isEmpty)
    }

    @Test
    func titleAndDescriptionAreBothTrimmedBeforeTheyAreSent() async {
        let fake = FakeCollectionManaging()
        let model = CollectionCreateModel(language: .ja, repo: fake)
        model.title = "  生活日常  "
        model.description = "  每天都會用到  "

        #expect(model.canCreate)
        _ = await model.create()

        #expect(fake.createdPayloads.count == 1)
        #expect(fake.createdPayloads.first?.title == "生活日常")
        // The old sheet trimmed only to test for emptiness, then sent the raw text.
        #expect(fake.createdPayloads.first?.description == "每天都會用到")
    }

    @Test
    func aWhitespaceOnlyDescriptionIsSentAsNoDescription() async {
        let fake = FakeCollectionManaging()
        let model = CollectionCreateModel(language: .ja, repo: fake)
        model.title = "生活日常"
        model.description = "   "

        _ = await model.create()

        #expect(fake.createdPayloads.first?.description == nil)
    }

    @Test
    func aFailedCreateSurfacesTheErrorAndStopsCreating() async {
        let fake = FakeCollectionManaging()
        fake.createError = AtlasFakeError.boom
        let model = CollectionCreateModel(language: .ja, repo: fake)
        model.title = "生活日常"

        let created = await model.create()

        #expect(created == nil)
        #expect(model.errorMessage != nil)
        #expect(!model.creating)
        #expect(model.canCreate)
    }

    @Test
    func theLanguageComesFromTheModelNotTheCallSite() async {
        let fake = FakeCollectionManaging()
        let model = CollectionCreateModel(language: .en, repo: fake)
        model.title = "Everyday"

        _ = await model.create()

        #expect(fake.createdPayloads.first?.language == .en)
    }
}

@MainActor
struct CollectionCandidatesModelTests {
    private func candidate(_ id: String, eligible: Bool? = nil) -> AtlasPublicItem {
        var item = AtlasPublicItem(
            id: id,
            slug: "slug-\(id)",
            lemma: "lemma-\(id)",
            displayZhHant: "中文",
            targetLanguage: .ja,
            category: nil,
            imageUrl: nil,
            author: nil,
            publishedAt: nil
        )
        item.eligible = eligible
        return item
    }

    /// The headline 合集 rule finally has a client expression: the server marks
    /// what it would refuse, and the picker stops offering it.
    @Test
    func itemsTheServerMarkedIneligibleAreNotOffered() async {
        let fake = FakeCollectionManaging()
        fake.candidates = [
            self.candidate("ok", eligible: true),
            self.candidate("rejected", eligible: false),
            self.candidate("unknown")
        ]
        let model = CollectionCandidatesModel(language: .ja, existingIds: [], repo: fake)

        await model.load()

        // An item that omits the flag stays allowed, so an older server never
        // empties the whole picker.
        #expect(model.available.map(\.id) == ["ok", "unknown"])
    }

    @Test
    func currentMembersDropOut() async {
        let fake = FakeCollectionManaging()
        fake.candidates = [self.candidate("a"), self.candidate("b")]
        let model = CollectionCandidatesModel(language: .ja, existingIds: ["a"], repo: fake)

        await model.load()

        #expect(model.available.map(\.id) == ["b"])
        #expect(!model.loading)
    }

    @Test
    func aFailedLoadSurfacesTheErrorAndClearsLoading() async {
        let fake = FakeCollectionManaging()
        fake.candidatesError = AtlasFakeError.boom
        let model = CollectionCandidatesModel(language: .ja, existingIds: [], repo: fake)

        await model.load()

        #expect(model.loadError != nil)
        #expect(!model.loading)
        #expect(model.available.isEmpty)
    }

    @Test
    func addTicksTheTileImmediately() async {
        let fake = FakeCollectionManaging()
        fake.candidates = [self.candidate("a")]
        let model = CollectionCandidatesModel(language: .ja, existingIds: [], repo: fake)
        await model.load()

        await model.add("a", using: { _ in true })

        #expect(model.isAdded("a"))
        #expect(model.addError == nil)
    }

    /// The bug: the tick went in before the await and never came back out, so a
    /// 合集 that refused the item still showed it as added.
    @Test
    func aFailedAddUnticksTheTileAndSaysSo() async {
        let fake = FakeCollectionManaging()
        fake.candidates = [self.candidate("a")]
        let model = CollectionCandidatesModel(language: .ja, existingIds: [], repo: fake)
        await model.load()

        await model.add("a", using: { _ in false })

        #expect(!model.isAdded("a"))
        #expect(model.addError != nil)
    }

    @Test
    func addingTheSameItemTwiceOnlyCallsThroughOnce() async {
        let fake = FakeCollectionManaging()
        let model = CollectionCandidatesModel(language: .ja, existingIds: [], repo: fake)
        var calls = 0

        await model.add("a", using: { _ in calls += 1
            return true
        })
        await model.add("a", using: { _ in calls += 1
            return true
        })

        #expect(calls == 1)
    }
}

// MARK: - Fake

@MainActor
private final class FakeCollectionManaging: CollectionManaging {
    struct CreatePayload {
        let title: String
        let description: String?
        let language: TargetLanguage
    }

    var collections: [AtlasMyCollection] = []
    var candidates: [AtlasPublicItem] = []
    var createError: Error?
    var candidatesError: Error?

    private(set) var createdPayloads: [CreatePayload] = []
    private(set) var deletedIds: [String] = []

    func myCollections() async throws -> [AtlasMyCollection] {
        self.collections
    }

    func createCollection(
        title: String,
        description: String?,
        targetLanguage: TargetLanguage
    ) async throws
        -> AtlasMyCollection
    {
        if let createError { throw createError }
        self.createdPayloads.append(
            CreatePayload(title: title, description: description, language: targetLanguage)
        )
        return AtlasMyCollection(
            id: "new",
            slug: "new",
            title: title,
            description: description,
            targetLanguage: targetLanguage,
            reviewStatus: "draft",
            itemCount: 0,
            avatarColor: nil,
            avatarImageUrl: nil,
            coverImageUrl: nil,
            publishedAt: nil,
            updatedAt: nil
        )
    }

    func deleteCollection(id: String) async throws {
        self.deletedIds.append(id)
    }

    func collectionCandidates(lang _: TargetLanguage) async throws -> [AtlasPublicItem] {
        if let candidatesError { throw candidatesError }
        return self.candidates
    }
}
