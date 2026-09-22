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
        var item = AtlasPublicItem(
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
        item.publicItemId = id
        item.publicationState = "public"
        return item
    }

    private func edit(
        cover: String? = nil,
        title: String = "My Collection",
        description: String? = nil,
        status: String = "draft",
        avatarColor: String? = nil,
        avatarPreviewUrl: String? = nil
    )
        -> AtlasCollectionEdit
    {
        AtlasCollectionEdit(
            id: "col1",
            slug: "s",
            title: title,
            description: description,
            targetLanguage: .ja,
            reviewStatus: status,
            avatarColor: avatarColor,
            avatarPreviewUrl: avatarPreviewUrl,
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
    func ownerItemStatusDecodesAndCountsUnpublishedMembers() async throws {
        let data = Data(
            #"{"id":"private-1","slug":"private-1","lemma":"cat","displayZhHant":"貓","targetLanguage":"ja","category":null,"imageUrl":"https://example.test/thumb","author":null,"publishedAt":null,"publicItemId":null,"reviewStatus":"draft","publicationState":"private"}"#
                .utf8
        )
        let privateItem = try JSONDecoder.tuji.decode(AtlasPublicItem.self, from: data)
        #expect(privateItem.collectionPublicationLabel != nil)

        let fake = FakeCollectionEditing(
            response: .init(collection: self.edit(), items: [privateItem])
        )
        let vm = CollectionEditVM(collectionId: "col1", repo: fake)
        await vm.load()
        #expect(vm.unpublishedMemberCount == 1)
    }

    @Test
    func avatarUploadReplacesThePublicImageAndFallbackColorTogether() async {
        let fake = FakeCollectionEditing(
            response: .init(
                collection: self.edit(
                    avatarColor: "#335577",
                    avatarPreviewUrl: "https://private.example/old"
                ),
                items: []
            )
        )
        fake.avatarResponse = AtlasCollectionAvatarResponse(
            ok: true,
            avatarColor: "#cc7733",
            avatarImageUrl: "https://public.example/new",
            avatarPreviewUrl: "https://public.example/new"
        )
        let vm = CollectionEditVM(collectionId: "col1", repo: fake)
        await vm.load()

        let color = await vm.updateAvatar(Data([1, 2, 3]))

        #expect(color == "#cc7733")
        #expect(vm.avatarColor == "#cc7733")
        #expect(vm.avatarPreviewURL?.absoluteString == "https://public.example/new")
        #expect(!vm.uploadingAvatar)
    }

    @Test
    func failedAvatarUploadKeepsTheAcceptedIdentity() async {
        let fake = FakeCollectionEditing(
            response: .init(
                collection: self.edit(
                    avatarColor: "#335577",
                    avatarPreviewUrl: "https://private.example/old"
                ),
                items: []
            )
        )
        fake.avatarError = FakeError.boom
        let vm = CollectionEditVM(collectionId: "col1", repo: fake)
        await vm.load()

        #expect(await vm.updateAvatar(Data([1, 2, 3])) == nil)
        #expect(vm.avatarColor == "#335577")
        #expect(vm.avatarPreviewURL?.absoluteString == "https://private.example/old")
        #expect(vm.errorMessage != nil)
        #expect(!vm.uploadingAvatar)
    }

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

    // MARK: - 取消公開

    // Publishing a 合集 used to be one-way: the browse feed kept it forever and
    // the only escape was deleting the collection.

    @Test
    func withdrawTakesTheCollectionOffTheFeedAndKeepsItsMembers() async {
        let fake = FakeCollectionEditing(
            response: .init(
                collection: self.edit(status: "approved"),
                items: [self.item(id: "a"), self.item(id: "b")]
            )
        )
        let vm = CollectionEditVM(collectionId: "col1", repo: fake)
        await vm.load()
        #expect(vm.canWithdraw)

        #expect(await vm.withdraw())

        #expect(fake.callLog.contains("withdraw"))
        // Reloaded from the server rather than patched locally.
        #expect(vm.collection?.review == .withdrawn)
        // The shelf came down; the photos on it did not.
        #expect(vm.members.count == 2)
    }

    /// Publishing must stay reachable afterwards — that is the whole difference
    /// between 取消公開 and a moderation takedown.
    @Test
    func aWithdrawnCollectionCanBePublishedAgain() async {
        let fake = FakeCollectionEditing(
            response: .init(collection: self.edit(status: "withdrawn"), items: [self.item(id: "a")])
        )
        let vm = CollectionEditVM(collectionId: "col1", repo: fake)
        await vm.load()

        #expect(vm.canSubmit)
        #expect(vm.canWithdraw == false)
    }

    @Test
    func aTakenDownCollectionOffersNeitherAction() async {
        let fake = FakeCollectionEditing(
            response: .init(collection: self.edit(status: "takedown"), items: [self.item(id: "a")])
        )
        let vm = CollectionEditVM(collectionId: "col1", repo: fake)
        await vm.load()

        #expect(vm.canSubmit == false)
        #expect(vm.canWithdraw == false)
    }

    @Test
    func aFailedWithdrawSurfacesTheErrorAndLeavesTheStatusAlone() async {
        let fake = FakeCollectionEditing(
            response: .init(collection: self.edit(status: "approved"), items: [self.item(id: "a")])
        )
        fake.withdrawError = APIError.forbidden
        let vm = CollectionEditVM(collectionId: "col1", repo: fake)
        await vm.load()

        #expect(await vm.withdraw() == false)
        #expect(vm.errorMessage != nil)
        #expect(vm.collection?.review == .approved)
    }

    // MARK: - 儲存 is lit by a real difference

    @Test
    func theFormIsCleanUntilItIsTypedIntoAndSavingMakesItCleanAgain() async {
        let fake = FakeCollectionEditing(
            response: .init(collection: self.edit(title: "T", description: "D"), items: [])
        )
        let vm = CollectionEditVM(collectionId: "col1", repo: fake)
        await vm.load()

        // A screen nobody has touched has nothing to write.
        #expect(!vm.isMetaDirty)
        #expect(!vm.canSaveMeta)

        vm.title = "T2"
        #expect(vm.isMetaDirty)
        #expect(vm.canSaveMeta)

        let saved = await vm.saveMeta()

        #expect(saved)
        #expect(vm.metaSaved)
        #expect(!vm.isMetaDirty)
        #expect(!vm.canSaveMeta)
    }

    @Test
    func whitespaceAloneIsNotAnEdit() async {
        let fake = FakeCollectionEditing(
            response: .init(collection: self.edit(title: "T", description: "D"), items: [])
        )
        let vm = CollectionEditVM(collectionId: "col1", repo: fake)
        await vm.load()

        vm.title = "T  "
        vm.description = "D\n"

        #expect(!vm.isMetaDirty)
    }

    @Test
    func aBlankTitleCannotBeSavedEvenThoughTheFormChanged() async {
        let fake = FakeCollectionEditing(
            response: .init(collection: self.edit(title: "T"), items: [])
        )
        let vm = CollectionEditVM(collectionId: "col1", repo: fake)
        await vm.load()

        vm.title = "   "

        #expect(vm.isMetaDirty)
        #expect(!vm.canSaveMeta)
    }

    @Test
    func aFailedSaveLeavesTheFormDirty() async {
        let fake = FakeCollectionEditing(
            response: .init(collection: self.edit(title: "T"), items: [])
        )
        fake.updateError = FakeError.boom
        let vm = CollectionEditVM(collectionId: "col1", repo: fake)
        await vm.load()
        vm.title = "T2"

        let saved = await vm.saveMeta()

        #expect(!saved)
        #expect(!vm.metaSaved)
        // 儲存 must stay lit over text the server does not have.
        #expect(vm.canSaveMeta)
        #expect(vm.errorMessage != nil)
    }

    @Test
    func publishBanksTheSavedMetaEvenWhenTheReloadFails() async {
        let fake = FakeCollectionEditing(
            response: .init(collection: self.edit(title: "T"), items: [self.item(id: "a")]),
            moderation: self.moderation(published: true)
        )
        let vm = CollectionEditVM(collectionId: "col1", repo: fake)
        await vm.load()
        vm.title = "T2"
        // The write lands; reading the row back does not.
        fake.editError = FakeError.boom

        _ = await vm.submit()

        // submit() persists the meta itself, so 儲存 must not stay lit over text
        // the server already has.
        #expect(!vm.isMetaDirty)
    }

    @Test
    func withdrawKeepsTextThatWasTypedButNotSaved() async {
        let fake = FakeCollectionEditing(
            response: .init(collection: self.edit(title: "T", status: "approved"), items: [self.item(id: "a")])
        )
        let vm = CollectionEditVM(collectionId: "col1", repo: fake)
        await vm.load()
        vm.title = "T2"

        let withdrawn = await vm.withdraw()

        #expect(withdrawn)
        #expect(vm.collection?.review == .withdrawn)
        // The reload must not take the unsaved title with it.
        #expect(vm.title == "T2")
        #expect(vm.isMetaDirty)
    }

    @Test
    func aRefusedRemoveReportsBesideTheRowsAndKeepsUnsavedText() async {
        let fake = FakeCollectionEditing(
            response: .init(collection: self.edit(title: "T"), items: [self.item(id: "a")])
        )
        fake.removeError = FakeError.boom
        let vm = CollectionEditVM(collectionId: "col1", repo: fake)
        await vm.load()
        vm.title = "T2"

        await vm.removeMember("a")

        // Member failures have their own line next to the rows; the page-level
        // error is for the publish gate.
        #expect(vm.memberError != nil)
        #expect(vm.errorMessage == nil)
        #expect(vm.title == "T2")
    }

    // MARK: - 刪除（從 MyCollectionsVM 搬來：刪除現在住在這個畫面）

    @Test
    func deleteReportsWhatItTookDownAndLeavesTheScreen() async {
        let fake = FakeCollectionEditing(
            response: .init(collection: self.edit(status: "approved"), items: [self.item(id: "a")])
        )
        let vm = CollectionEditVM(collectionId: "col1", repo: fake)
        await vm.load()
        let spy = SpyMutationRefreshing()

        let deleted = await vm.delete(refreshing: spy)

        #expect(deleted)
        #expect(fake.callLog.contains("delete"))
        // 物見 has to be told, because this one was on the wall.
        #expect(spy.events == [.collectionDeleted(wasPublic: true)])
    }

    @Test
    func deletingADraftDoesNotClaimItWasPublic() async {
        let fake = FakeCollectionEditing(
            response: .init(collection: self.edit(status: "draft"), items: [self.item(id: "a")])
        )
        let vm = CollectionEditVM(collectionId: "col1", repo: fake)
        await vm.load()
        let spy = SpyMutationRefreshing()

        _ = await vm.delete(refreshing: spy)

        #expect(spy.events == [.collectionDeleted(wasPublic: false)])
    }

    /// A failed delete must not report a mutation: 物見's feed would drop its
    /// cache for a 合集 that is still there.
    @Test
    func aFailedDeleteSurfacesTheErrorAndReportsNothing() async {
        let fake = FakeCollectionEditing(
            response: .init(collection: self.edit(status: "approved"), items: [self.item(id: "a")])
        )
        fake.deleteError = FakeError.boom
        let vm = CollectionEditVM(collectionId: "col1", repo: fake)
        await vm.load()
        let spy = SpyMutationRefreshing()

        let deleted = await vm.delete(refreshing: spy)

        #expect(!deleted)
        #expect(vm.errorMessage != nil)
        #expect(spy.events.isEmpty)
    }

    /// Two taps on an irreversible button must not send two deletes.
    @Test
    func aSecondDeleteMidFlightIsIgnored() async {
        let fake = FakeCollectionEditing(
            response: .init(collection: self.edit(status: "draft"), items: [self.item(id: "a")])
        )
        let vm = CollectionEditVM(collectionId: "col1", repo: fake)
        await vm.load()
        fake.onDelete = { [weak vm] in
            _ = await vm?.delete(refreshing: SpyMutationRefreshing())
        }

        _ = await vm.delete(refreshing: SpyMutationRefreshing())

        #expect(fake.callLog.count { $0 == "delete" } == 1)
    }

    @Test
    func theDeleteWarningFollowsWhereTheCollectionStands() async {
        for (status, warning) in [
            ("approved", CollectionDeleteWarning.takesDownFromPublic),
            ("pending_review", .cancelsReview),
            ("draft", .privateOnly),
            ("withdrawn", .privateOnly)
        ] {
            let fake = FakeCollectionEditing(
                response: .init(collection: self.edit(status: status), items: [])
            )
            let vm = CollectionEditVM(collectionId: "col1", repo: fake)
            await vm.load()
            #expect(vm.deleteWarning == warning)
        }
    }
}

@MainActor
private final class SpyMutationRefreshing: AtlasMutationRefreshing {
    private(set) var events: [AtlasMutation] = []

    func refresh(after event: AtlasMutation) async {
        self.events.append(event)
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
    var withdrawError: Error?
    var updateError: Error?
    var removeError: Error?
    var deleteError: Error?
    var onDelete: (() async -> Void)?
    /// Fails the *reload*, not the first load: set it after `load()` to model a
    /// server that takes the write and then cannot be read back.
    var editError: Error?
    var avatarResponse: AtlasCollectionAvatarResponse?
    var avatarError: Error?

    init(response: AtlasCollectionEditResponse, moderation: AtlasPublishModeration? = nil) {
        self.response = response
        self.moderation = moderation
    }

    func collectionEdit(id _: String) async throws -> AtlasCollectionEditResponse {
        self.callLog.append("edit")
        if let editError { throw editError }
        return self.response
    }

    func updateCollection(
        id _: String,
        title _: String,
        description _: String?,
        coverPublicItemId _: String?
    ) async throws {
        self.callLog.append("update")
        if let updateError { throw updateError }
    }

    func updateCollectionAvatar(id _: String, imageData _: Data) async throws
        -> AtlasCollectionAvatarResponse
    {
        self.callLog.append("avatar")
        if let avatarError { throw avatarError }
        return self.avatarResponse ?? AtlasCollectionAvatarResponse(
            ok: true,
            avatarColor: "#5f7f9f",
            avatarImageUrl: "https://public.example/default",
            avatarPreviewUrl: nil
        )
    }

    func addCollectionItem(id _: String, publicItemId _: String) async throws {
        self.callLog.append("add")
    }

    func removeCollectionItem(id _: String, publicItemId _: String) async throws {
        self.callLog.append("remove")
        if let removeError { throw removeError }
    }

    func publishCollection(id _: String) async throws -> AtlasCollectionPublishResponse {
        self.callLog.append("publish")
        if let publishError { throw publishError }
        return AtlasCollectionPublishResponse(moderation: self.moderation)
    }

    func deleteCollection(id _: String) async throws {
        self.callLog.append("delete")
        // Runs while a delete is in flight, so a test can re-enter the VM the
        // way a second tap would.
        if let onDelete { await onDelete() }
        if let deleteError { throw deleteError }
    }

    func withdrawCollection(id _: String) async throws -> AtlasWithdrawResponse {
        self.callLog.append("withdraw")
        if let withdrawError { throw withdrawError }
        // Mirror the server: the reloaded collection comes back withdrawn.
        let current = self.response.collection
        self.response = AtlasCollectionEditResponse(
            collection: AtlasCollectionEdit(
                id: current.id,
                slug: current.slug,
                title: current.title,
                description: current.description,
                targetLanguage: current.targetLanguage,
                reviewStatus: "withdrawn",
                avatarColor: current.avatarColor,
                avatarPreviewUrl: current.avatarPreviewUrl,
                coverPublicItemId: current.coverPublicItemId,
                coverImageUrl: current.coverImageUrl,
                publishedAt: current.publishedAt,
                updatedAt: current.updatedAt
            ),
            items: self.response.items
        )
        return AtlasWithdrawResponse(ok: true, reviewStatus: "withdrawn")
    }
}
