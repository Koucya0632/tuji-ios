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
            avatarColor: nil,
            avatarImageUrl: nil,
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

    private func context(
        isSignedIn: Bool = false,
        username: String? = nil,
        autoSave: Bool = false
    )
        -> CollectionDetailVM.OpenContext
    {
        .init(
            isSignedIn: isSignedIn,
            username: username,
            autoSave: autoSave
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

        await vm.open(context: self.context())

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

        await vm.open(context: self.context())

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

        await vm.open(context: self.context())

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

        await vm.open(context: self.context(
            isSignedIn: true,
            username: "other"
        ))

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
        #expect(saved?.collection.saveCount == 7)
        #expect(saved?.isSaved == true)
        #expect(vm.isSaved)
        #expect(vm.bookmarkLoaded)
    }

    @Test
    func lockedResponseKeepsOnlyTheServerPreviewAndAccessCounts() async {
        let fake = FakeCollectionDetailReading()
        var response = AtlasCollectionDetailResponse(
            collection: self.collection(id: "a"),
            items: [self.item(id: "x")]
        )
        response.access = AtlasCollectionAccess(
            unlocked: false,
            isOwner: false,
            isSaved: false,
            totalCount: 12,
            learningCount: 0
        )
        fake.result = .success(response)
        let vm = CollectionDetailVM(slug: "s", repo: fake)

        await vm.open(context: self.context())

        #expect(!vm.unlocked)
        #expect(vm.items.count == 1)
        #expect(vm.totalCount == 12)
        #expect(vm.remainingLearningCount == 12)
    }

    /// 收藏 is what opens the member list, and `unlocked` only ever came from
    /// the server's `access`, so a save that did not re-read the detail left the
    /// screen locked — 「收藏合集後查看全部 N 個內容」 stayed up, the members
    /// stayed unopenable and 全部加入學習 never appeared, until the user backed
    /// out and came in again.
    @Test
    func savingUnlocksTheMemberListWithoutLeavingTheScreen() async {
        let details = FakeCollectionDetailReading()
        let bookmarks = FakeDetailBookmarking()

        var locked = AtlasCollectionDetailResponse(
            collection: self.collection(id: "a"),
            items: [self.item(id: "x")]
        )
        locked.access = AtlasCollectionAccess(
            unlocked: false,
            isOwner: false,
            isSaved: false,
            totalCount: 3,
            learningCount: 0
        )
        details.result = .success(locked)

        let vm = CollectionDetailVM(
            slug: "s",
            repo: details,
            bookmarkRepo: bookmarks
        )
        await vm.open(context: self.context(isSignedIn: true, username: "other"))
        #expect(!vm.unlocked)
        #expect(vm.items.count == 1)

        // Unlocking is not a flag flip: the locked response only carried a
        // preview, so the full catalogue arrives with the re-read.
        var unlocked = AtlasCollectionDetailResponse(
            collection: self.collection(id: "a"),
            items: [self.item(id: "x"), self.item(id: "y"), self.item(id: "z")]
        )
        unlocked.access = AtlasCollectionAccess(
            unlocked: true,
            isOwner: false,
            isSaved: true,
            totalCount: 3,
            learningCount: 0
        )
        details.result = .success(unlocked)
        bookmarks.saveResult = .success(.init(ok: true, saved: true, saveCount: 1))

        await vm.save()

        #expect(vm.isSaved)
        #expect(vm.unlocked)
        #expect(vm.items.count == 3)
        #expect(vm.remainingLearningCount == 3)
    }

    @Test
    func ownerSaveDoesNotCostASecondDetailFetch() async {
        let recorder = DetailCallRecorder()
        let details = FakeCollectionDetailReading(recorder: recorder)
        let bookmarks = FakeDetailBookmarking(recorder: recorder)

        var response = AtlasCollectionDetailResponse(
            collection: self.collection(id: "a"),
            items: [self.item(id: "x")]
        )
        // An owner is unlocked whatever their bookmark says, so nothing about
        // the lock can change and the re-read would be pure waste.
        response.access = AtlasCollectionAccess(
            unlocked: true,
            isOwner: true,
            isSaved: false,
            totalCount: 1,
            learningCount: 0
        )
        details.result = .success(response)

        let vm = CollectionDetailVM(
            slug: "s",
            repo: details,
            bookmarkRepo: bookmarks
        )
        await vm.open(context: self.context(isSignedIn: true, username: "u"))
        await vm.save()

        #expect(recorder.calls.count(where: { $0 == .detail }) == 1)
    }

    @Test
    func batchLearningUpdatesCountsAndRefreshesStudyData() async {
        let details = FakeCollectionDetailReading()
        var response = AtlasCollectionDetailResponse(
            collection: self.collection(id: "a"),
            items: [self.item(id: "x"), self.item(id: "y")]
        )
        response.access = AtlasCollectionAccess(
            unlocked: true,
            isOwner: false,
            isSaved: true,
            totalCount: 2,
            learningCount: 1
        )
        details.result = .success(response)
        let learning = FakeCollectionLearning()
        let refresher = RecordingCollectionLearningRefresher()
        let vm = CollectionDetailVM(
            slug: "s",
            repo: details,
            learningRepo: learning,
            learningRefresher: refresher
        )

        await vm.open(context: self.context())
        let learned = await vm.learnRemaining()

        #expect(learned)
        #expect(vm.learningCount == 2)
        #expect(vm.remainingLearningCount == 0)
        #expect(refresher.refreshCount == 1)
        #expect(learning.loadedSlugs == ["s"])
    }

    @Test
    func failedBatchLearningDoesNotRefreshClientLearningData() async {
        let details = FakeCollectionDetailReading()
        var response = AtlasCollectionDetailResponse(
            collection: self.collection(id: "a"),
            items: [self.item(id: "x")]
        )
        response.access = AtlasCollectionAccess(
            unlocked: true,
            isOwner: false,
            isSaved: true,
            totalCount: 1,
            learningCount: 0
        )
        details.result = .success(response)
        let learning = FakeCollectionLearning()
        learning.result = .failure(FakeError.boom)
        let refresher = RecordingCollectionLearningRefresher()
        let vm = CollectionDetailVM(
            slug: "s",
            repo: details,
            learningRepo: learning,
            learningRefresher: refresher
        )

        await vm.open(context: self.context())
        let learned = await vm.learnRemaining()

        #expect(!learned)
        #expect(refresher.refreshCount == 0)
        #expect(vm.learningActionError != nil)
    }

    @Test
    func autoSaveContinuesAfterBookmarkStateFailureInWorkflowOrder() async {
        let recorder = DetailCallRecorder()
        let details = FakeCollectionDetailReading(recorder: recorder)
        let bookmarks = FakeDetailBookmarking(recorder: recorder)
        bookmarks.stateResult = .failure(FakeError.boom)
        let vm = CollectionDetailVM(
            slug: "s",
            repo: details,
            bookmarkRepo: bookmarks
        )

        let change = await vm.open(context: self.context(
            isSignedIn: true,
            username: "other",
            autoSave: true
        ))

        #expect(recorder.calls == [.detail, .bookmarkState, .save])
        #expect(change?.isSaved == true)
        #expect(vm.isSaved)
    }

    @Test
    func serverOwnerSkipsBookmarkWorkflowEvenWhenFallbackWouldDisagree() async {
        let recorder = DetailCallRecorder()
        let details = FakeCollectionDetailReading(recorder: recorder)
        var response = AtlasCollectionDetailResponse(
            collection: self.collection(id: "a"),
            items: []
        )
        response.access = AtlasCollectionAccess(
            unlocked: true,
            isOwner: true,
            isSaved: false,
            totalCount: 0,
            learningCount: 0
        )
        details.result = .success(response)
        let bookmarks = FakeDetailBookmarking(recorder: recorder)
        let vm = CollectionDetailVM(
            slug: "s",
            repo: details,
            bookmarkRepo: bookmarks
        )

        let change = await vm.open(context: self.context(
            isSignedIn: true,
            username: "different-user",
            autoSave: true
        ))

        #expect(recorder.calls == [.detail])
        #expect(change == nil)
        #expect(vm.isOwner)
    }

    @Test
    func legacyResponseUsesCaseInsensitiveOwnerFallback() async {
        let recorder = DetailCallRecorder()
        let details = FakeCollectionDetailReading(recorder: recorder)
        let bookmarks = FakeDetailBookmarking(recorder: recorder)
        let vm = CollectionDetailVM(
            slug: "s",
            repo: details,
            bookmarkRepo: bookmarks
        )

        await vm.open(context: self.context(
            isSignedIn: true,
            username: "U",
            autoSave: true
        ))

        #expect(recorder.calls == [.detail])
        #expect(vm.isOwner)
    }

    @Test
    func failedDetailLoadStopsBeforePrivateWorkflow() async {
        let recorder = DetailCallRecorder()
        let details = FakeCollectionDetailReading(recorder: recorder)
        details.result = .failure(FakeError.boom)
        let bookmarks = FakeDetailBookmarking(recorder: recorder)
        let vm = CollectionDetailVM(
            slug: "s",
            repo: details,
            bookmarkRepo: bookmarks
        )

        let change = await vm.open(context: self.context(
            isSignedIn: true,
            username: "other",
            autoSave: true
        ))

        #expect(recorder.calls == [.detail])
        #expect(change == nil)
    }
}

// MARK: - Fake

private enum FakeError: Error {
    case boom
}

@MainActor
private final class DetailCallRecorder {
    enum Call: Equatable {
        case detail
        case bookmarkState
        case save
        case unsave
    }

    private(set) var calls: [Call] = []

    func record(_ call: Call) {
        self.calls.append(call)
    }
}

@MainActor
private final class FakeCollectionDetailReading: CollectionDetailReading {
    private let recorder: DetailCallRecorder?

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
                avatarColor: nil,
                avatarImageUrl: nil,
                coverImageUrl: nil,
                publishedAt: nil
            ),
            items: []
        )
    )

    init(recorder: DetailCallRecorder? = nil) {
        self.recorder = recorder
    }

    func collection(slug _: String) async throws -> AtlasCollectionDetailResponse {
        self.recorder?.record(.detail)
        return try self.result.get()
    }
}

@MainActor
private final class FakeDetailBookmarking: CollectionBookmarking {
    private let recorder: DetailCallRecorder?

    var stateResult: Result<AtlasSaveResponse, Error> = .success(
        .init(ok: true, saved: false, saveCount: 0)
    )
    var saveResult: Result<AtlasSaveResponse, Error> = .success(
        .init(ok: true, saved: true, saveCount: 1)
    )

    init(recorder: DetailCallRecorder? = nil) {
        self.recorder = recorder
    }

    func savedCollections(lang _: TargetLanguage) async throws -> [AtlasCollection] {
        []
    }

    func collectionSaveState(slug _: String) async throws -> AtlasSaveResponse {
        self.recorder?.record(.bookmarkState)
        return try self.stateResult.get()
    }

    func saveCollection(slug _: String) async throws -> AtlasSaveResponse {
        self.recorder?.record(.save)
        return try self.saveResult.get()
    }

    func unsaveCollection(slug _: String) async throws -> AtlasSaveResponse {
        self.recorder?.record(.unsave)
        return .init(ok: true, saved: false, saveCount: 0)
    }
}

@MainActor
private final class FakeCollectionLearning: CollectionLearning {
    private(set) var loadedSlugs: [String] = []
    var result: Result<AtlasCollectionLearnResponse, Error> = .success(
        AtlasCollectionLearnResponse(
            ok: true,
            addedCount: 1,
            learningCount: 2,
            totalCount: 2
        )
    )

    func learnCollection(slug: String) async throws -> AtlasCollectionLearnResponse {
        self.loadedSlugs.append(slug)
        return try self.result.get()
    }
}

@MainActor
private final class RecordingCollectionLearningRefresher: CommunityLearningRefreshing {
    private(set) var refreshCount = 0

    func refreshAfterLearningMutation() async {
        self.refreshCount += 1
    }
}
