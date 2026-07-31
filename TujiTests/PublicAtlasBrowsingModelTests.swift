// Pins the unified 公開圖鑑 browsing module: explore cache protection, saved-shelf
// authentication and language scoping, refresh policy, and confirmed bookmark
// reconciliation. Fakes are synchronous at the repository seam so the state
// machine remains deterministic under @MainActor.

import Foundation
import Testing
@testable import Tuji

@MainActor
struct PublicAtlasBrowsingModelTests {
    @Test
    func initialUpdateLoadsExploreAndMarksItReady() async {
        let explore = FakeCollectionsBrowsing()
        explore.result = .success([self.collection("a")])
        let model = self.model(explore: explore)

        await model.update(shelf: .explore, language: .ja, isSignedIn: false)

        #expect(model.explore.collections.map(\.id) == ["a"])
        #expect(model.explore.phase == .ready)
        #expect(model.explore.loadedLanguage == .ja)
    }

    @Test
    func returningToSameNonEmptyExploreShelfDoesNotReload() async {
        let explore = FakeCollectionsBrowsing()
        explore.result = .success([self.collection("a")])
        let model = self.model(explore: explore)

        await model.update(shelf: .explore, language: .ja, isSignedIn: false)
        await model.update(shelf: .explore, language: .ja, isSignedIn: false)

        #expect(explore.calls.count == 1)
    }

    @Test
    func languageChangeReloadsExploreShelf() async {
        let explore = FakeCollectionsBrowsing()
        explore.result = .success([self.collection("a")])
        let model = self.model(explore: explore)

        await model.update(shelf: .explore, language: .ja, isSignedIn: false)
        await model.update(shelf: .explore, language: .en, isSignedIn: false)

        #expect(explore.calls.map(\.language) == [.ja, .en])
    }

    @Test
    func pendingPublishAndPullRefreshBothBypassExploreCache() async {
        let explore = FakeCollectionsBrowsing()
        explore.result = .success([self.collection("a")])
        let model = self.model(explore: explore)

        await model.update(shelf: .explore, language: .ja, isSignedIn: false)
        await model.update(
            shelf: .explore,
            language: .ja,
            isSignedIn: false,
            pendingExploreRefresh: true
        )
        await model.refresh(shelf: .explore, language: .ja, isSignedIn: false)

        #expect(explore.calls.count == 3)
        #expect(explore.calls.dropFirst().map(\.forceReload) == [true, true])
    }

    @Test
    func failedInitialExploreLoadClearsListAndSurfacesError() async {
        let explore = FakeCollectionsBrowsing()
        explore.result = .failure(FakeBrowsingError.boom)
        let model = self.model(explore: explore)

        await model.update(shelf: .explore, language: .ja, isSignedIn: false)

        #expect(model.explore.collections.isEmpty)
        #expect(model.explore.errorMessage != nil)
        if case .failed = model.explore.phase {} else {
            Issue.record("expected failed explore phase")
        }
    }

    @Test
    func failedExploreRefreshKeepsExistingList() async {
        let explore = FakeCollectionsBrowsing()
        explore.result = .success([self.collection("a"), self.collection("b")])
        let model = self.model(explore: explore)

        await model.update(shelf: .explore, language: .ja, isSignedIn: false)
        explore.result = .failure(FakeBrowsingError.boom)
        await model.refresh(shelf: .explore, language: .ja, isSignedIn: false)

        #expect(model.explore.collections.map(\.id) == ["a", "b"])
        #expect(model.explore.errorMessage != nil)
    }

    @Test
    func selectedSavedShelfLoadsOnlyForSignedInUser() async {
        let saved = FakeCollectionBookmarking()
        saved.saved = [self.collection("new"), self.collection("old")]
        let model = self.model(saved: saved)

        await model.update(shelf: .saved, language: .ja, isSignedIn: false)
        #expect(saved.requestedLanguages.isEmpty)
        #expect(model.saved.phase == .idle)

        await model.update(shelf: .saved, language: .ja, isSignedIn: true)
        #expect(saved.requestedLanguages == [.ja])
        #expect(model.saved.collections.map(\.id) == ["new", "old"])
        #expect(model.saved.phase == .ready)
    }

    @Test
    func sameSavedContextDoesNotReloadUntilRefreshed() async {
        let saved = FakeCollectionBookmarking()
        let model = self.model(saved: saved)

        await model.update(shelf: .saved, language: .ja, isSignedIn: true)
        await model.update(shelf: .saved, language: .ja, isSignedIn: true)
        #expect(saved.requestedLanguages.count == 1)

        await model.refresh(shelf: .saved, language: .ja, isSignedIn: true)
        #expect(saved.requestedLanguages.count == 2)
    }

    @Test
    func signingOutClearsPrivateShelfAndNextSignInReloadsIt() async {
        let saved = FakeCollectionBookmarking()
        saved.saved = [self.collection("a")]
        let model = self.model(saved: saved)

        await model.update(shelf: .saved, language: .ja, isSignedIn: true)
        await model.update(shelf: .explore, language: .ja, isSignedIn: false)

        #expect(model.saved.collections.isEmpty)
        #expect(model.saved.phase == .idle)

        await model.update(shelf: .saved, language: .ja, isSignedIn: true)
        #expect(saved.requestedLanguages == [.ja, .ja])
    }

    @Test
    func confirmedBookmarkChangeUpdatesBothShelves() async {
        let original = self.collection("a", saveCount: 0)
        let confirmed = self.collection("a", saveCount: 1)
        let explore = FakeCollectionsBrowsing()
        explore.result = .success([original])
        let model = self.model(explore: explore)
        await model.update(shelf: .explore, language: .ja, isSignedIn: true)

        model.applyConfirmedBookmark(
            collection: confirmed,
            isSaved: true,
            language: .ja
        )

        #expect(model.explore.collections == [confirmed])
        #expect(model.saved.collections == [confirmed])

        model.applyConfirmedBookmark(
            collection: confirmed,
            isSaved: false,
            language: .ja
        )
        #expect(model.saved.collections.isEmpty)
    }

    @Test
    func bookmarkChangeForAnotherLanguageDoesNotEnterSavedShelf() {
        let model = self.model()

        model.applyConfirmedBookmark(
            collection: self.collection("a", language: .en),
            isSaved: true,
            language: .ja
        )

        #expect(model.saved.collections.isEmpty)
    }

    private func model(
        explore: FakeCollectionsBrowsing = FakeCollectionsBrowsing(),
        saved: FakeCollectionBookmarking = FakeCollectionBookmarking()
    )
        -> PublicAtlasBrowsingModel
    {
        PublicAtlasBrowsingModel(exploreRepo: explore, savedRepo: saved)
    }

    private func collection(
        _ id: String,
        language: TargetLanguage = .ja,
        saveCount: Int = 0
    )
        -> AtlasCollection
    {
        AtlasCollection(
            id: id,
            slug: "slug-\(id)",
            title: id,
            description: nil,
            targetLanguage: language,
            author: AtlasAuthorRef(handle: "other", displayName: "Other", avatar: "face"),
            itemCount: 1,
            saveCount: saveCount,
            coverImageUrl: nil,
            publishedAt: nil
        )
    }
}

private enum FakeBrowsingError: Error {
    case boom
}

@MainActor
private final class FakeCollectionsBrowsing: CollectionsBrowsing {
    private(set) var calls: [(language: TargetLanguage, forceReload: Bool)] = []
    var result: Result<[AtlasCollection], Error> = .success([])

    func publicCollections(
        lang: TargetLanguage,
        forceReload: Bool
    ) async throws
        -> [AtlasCollection]
    {
        self.calls.append((lang, forceReload))
        return try self.result.get()
    }
}

@MainActor
private final class FakeCollectionBookmarking: CollectionBookmarking {
    var saved: [AtlasCollection] = []
    private(set) var requestedLanguages: [TargetLanguage] = []

    func savedCollections(lang: TargetLanguage) async throws -> [AtlasCollection] {
        self.requestedLanguages.append(lang)
        return self.saved
    }

    func collectionSaveState(slug _: String) async throws -> AtlasSaveResponse {
        AtlasSaveResponse(ok: true, saved: false, saveCount: 0)
    }

    func saveCollection(slug _: String) async throws -> AtlasSaveResponse {
        AtlasSaveResponse(ok: true, saved: true, saveCount: 1)
    }

    func unsaveCollection(slug _: String) async throws -> AtlasSaveResponse {
        AtlasSaveResponse(ok: true, saved: false, saveCount: 0)
    }
}
