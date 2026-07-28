// Pins CollectionEditVM's orchestration — the order-sensitive submit() (meta
// persists BEFORE the publish gate reads it), the empty-collection guard, the
// load seeding + cover fallback, and the published outcome the view reads to
// mark the public feed stale. Driven through a synchronous FakeCollectionEditing
// (no timers — CI @MainActor suites starve on real waits).

import Foundation
import Testing
@testable import Tuji

@MainActor
struct CollectionEditVMTests {
    // MARK: - Fixtures

    private func item(id: String, lemma: String = "cat") -> AtlasPublicItem {
        AtlasPublicItem(
            id: id,
            slug: "slug-\(id)",
            lemma: lemma,
            displayZhHant: "貓",
            targetLanguage: .ja,
            category: nil,
            imageUrl: nil,
            author: nil,
            publishedAt: nil
        )
    }

    private func edit(
        cover: String? = nil,
        title: String = "My Collection",
        description: String? = nil
    )
        -> AtlasCollectionEdit
    {
        AtlasCollectionEdit(
            id: "col1",
            slug: "s",
            title: title,
            description: description,
            targetLanguage: .ja,
            reviewStatus: "draft",
            coverPublicItemId: cover,
            coverImageUrl: nil,
            publishedAt: nil,
            updatedAt: nil
        )
    }

    private func moderation(published: Bool) -> AtlasPublishModeration {
        AtlasPublishModeration(
            reviewStatus: published ? "approved" : "pending_review",
            published: published
        )
    }

    // MARK: - Tests

    @Test
    func loadSeedsFormAndFallsBackToFirstItemAsCover() async {
        let fake = FakeCollectionEditing(
            response: .init(
                collection: self.edit(cover: nil, title: "T", description: "D"),
                items: [self.item(id: "a"), self.item(id: "b")]
            )
        )
        let vm = CollectionEditVM(collectionId: "col1", repo: fake)

        await vm.load()

        #expect(vm.title == "T")
        #expect(vm.description == "D")
        #expect(vm.members.count == 2)
        // No stored cover → fall back to the first member.
        #expect(vm.coverId == "a")
        #expect(vm.phase == .ready)
    }

    @Test
    func submitPersistsMetaBeforePublishing() async throws {
        let fake = FakeCollectionEditing(
            response: .init(collection: self.edit(), items: [self.item(id: "a")]),
            moderation: self.moderation(published: true)
        )
        let vm = CollectionEditVM(collectionId: "col1", repo: fake)
        await vm.load()

        let published = await vm.submit()

        // The invariant the code comment warns about: the meta write must land
        // before the publish gate reads the stored row.
        let update = try #require(fake.callLog.firstIndex(of: "update"))
        let publish = try #require(fake.callLog.firstIndex(of: "publish"))
        #expect(update < publish)
        #expect(published)
        #expect(vm.submitState == .done(self.moderation(published: true)))
    }

    @Test
    func submitIsBlockedAndTouchesNothingWithNoMembers() async {
        let fake = FakeCollectionEditing(
            response: .init(collection: self.edit(), items: [])
        )
        let vm = CollectionEditVM(collectionId: "col1", repo: fake)
        await vm.load()

        #expect(!vm.canSubmit)
        let published = await vm.submit()

        #expect(!published)
        // An empty collection must not reach the repository at all.
        #expect(!fake.callLog.contains("update"))
        #expect(!fake.callLog.contains("publish"))
    }

    @Test
    func queuedForReviewSurfacesUnpublishedOutcomeToTheView() async {
        let fake = FakeCollectionEditing(
            response: .init(collection: self.edit(), items: [self.item(id: "a")]),
            moderation: self.moderation(published: false)
        )
        let vm = CollectionEditVM(collectionId: "col1", repo: fake)
        await vm.load()

        let published = await vm.submit()

        #expect(!published)
        guard case let .done(outcome) = vm.submitState else {
            Issue.record("expected submitState == .done, got \(vm.submitState)")
            return
        }
        #expect(outcome?.published == false)
    }

    @Test
    func failedPublishSurfacesAsErrorAndReportsNotPublished() async {
        let fake = FakeCollectionEditing(
            response: .init(collection: self.edit(), items: [self.item(id: "a")])
        )
        fake.publishError = FakeError.boom
        let vm = CollectionEditVM(collectionId: "col1", repo: fake)
        await vm.load()

        let published = await vm.submit()

        #expect(!published)
        #expect(vm.errorMessage != nil)
        if case .failed = vm.submitState {} else {
            Issue.record("expected submitState == .failed, got \(vm.submitState)")
        }
    }
}

// MARK: - Fake

private enum FakeError: Error {
    case boom
}

@MainActor
private final class FakeCollectionEditing: CollectionEditing {
    private(set) var callLog: [String] = []
    var response: AtlasCollectionEditResponse
    var moderation: AtlasPublishModeration?
    var publishError: Error?

    init(response: AtlasCollectionEditResponse, moderation: AtlasPublishModeration? = nil) {
        self.response = response
        self.moderation = moderation
    }

    func collectionEdit(id _: String) async throws -> AtlasCollectionEditResponse {
        self.callLog.append("edit")
        return self.response
    }

    func updateCollection(
        id _: String,
        title _: String,
        description _: String?,
        coverPublicItemId _: String?
    ) async throws {
        self.callLog.append("update")
    }

    func addCollectionItem(id _: String, publicItemId _: String) async throws {
        self.callLog.append("add")
    }

    func removeCollectionItem(id _: String, publicItemId _: String) async throws {
        self.callLog.append("remove")
    }

    func publishCollection(id _: String) async throws -> AtlasCollectionPublishResponse {
        self.callLog.append("publish")
        if let publishError { throw publishError }
        return AtlasCollectionPublishResponse(moderation: self.moderation)
    }
}
