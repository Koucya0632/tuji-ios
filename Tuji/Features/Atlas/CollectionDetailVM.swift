// View model for AtlasCollectionDetailView (公開合集詳情). A load-and-render screen:
// fetches the collection + member items behind the CollectionDetailReading seam so
// the view stays presentation-only. Seeds from the feed card preview so the header
// renders instantly while the members load.

import Foundation
import Observation

@MainActor
@Observable
final class CollectionDetailVM {
    enum Phase: Equatable {
        case loading, ready, failed(String)
    }

    struct OpenContext: Equatable {
        let isSignedIn: Bool
        let username: String?
        let autoSave: Bool
    }

    struct BookmarkChange: Equatable {
        let collection: AtlasCollection
        let isSaved: Bool
    }

    let slug: String
    private(set) var collection: AtlasCollection?
    private(set) var items: [AtlasPublicItem] = []
    private(set) var phase: Phase = .loading
    private(set) var isSaved = false
    private(set) var bookmarkLoaded = false
    private(set) var bookmarkBusy = false
    private(set) var bookmarkError: String?
    private(set) var bookmarkActionError: String?
    private(set) var isUnavailable = false
    private(set) var unlocked = true
    private(set) var isOwner = false
    private(set) var totalCount = 0
    private(set) var learningCount = 0
    private(set) var learningBusy = false
    private(set) var learningActionError: String?

    private let repo: CollectionDetailReading
    private let bookmarkRepo: CollectionBookmarking
    private let learningRepo: CollectionLearning
    private let learningRefresher: CommunityLearningRefreshing

    init(
        slug: String,
        preview: AtlasCollection? = nil,
        repo: CollectionDetailReading = LiveAtlasRepository.shared,
        bookmarkRepo: CollectionBookmarking = LiveAtlasRepository.shared,
        learningRepo: CollectionLearning = LiveAtlasRepository.shared,
        learningRefresher: CommunityLearningRefreshing = LiveCommunityLearningRefresher()
    ) {
        self.slug = slug
        self.collection = preview
        self.totalCount = preview?.itemCount ?? 0
        self.repo = repo
        self.bookmarkRepo = bookmarkRepo
        self.learningRepo = learningRepo
        self.learningRefresher = learningRefresher
    }

    var errorMessage: String? {
        if case let .failed(message) = self.phase { return message }
        return nil
    }

    /// Open the collection through one workflow so the view cannot reorder the
    /// detail, ownership, bookmark-state, and deep-link auto-save steps.
    @discardableResult
    func open(context: OpenContext) async -> BookmarkChange? {
        guard await self.load(context: context) else { return nil }
        guard context.isSignedIn, !self.isOwner else { return nil }

        if !self.bookmarkLoaded {
            await self.loadBookmarkState()
        }

        guard context.autoSave, !self.isSaved else { return nil }
        return await self.save()
    }

    private func load(context: OpenContext) async -> Bool {
        self.phase = .loading
        self.isUnavailable = false
        self.bookmarkLoaded = false
        self.bookmarkError = nil
        self.bookmarkActionError = nil
        self.isSaved = false
        self.isOwner = self.matchesOwner(
            collection: self.collection,
            username: context.username
        )
        do {
            let response = try await self.repo.collection(slug: self.slug)
            self.collection = response.collection
            self.items = response.items
            if let access = response.access {
                self.unlocked = access.unlocked
                self.isOwner = access.isOwner
                self.isSaved = access.isSaved
                self.bookmarkLoaded = true
                self.totalCount = access.totalCount
                self.learningCount = access.learningCount
            } else {
                // Compatibility with older responses and lightweight test
                // fixtures, which always returned the complete catalog.
                self.unlocked = true
                self.isOwner = self.matchesOwner(
                    collection: response.collection,
                    username: context.username
                )
                self.totalCount = response.collection.itemCount
            }
            self.phase = .ready
            return true
        } catch {
            if case APIError.notFound = error {
                self.collection = nil
                self.items = []
                self.isUnavailable = true
            }
            // Keep any preview header on screen; the error state shows only when
            // there's nothing to render.
            self.phase = .failed(tujiUserMessage(for: error))
            return false
        }
    }

    private func loadBookmarkState() async {
        guard !self.bookmarkBusy else { return }
        self.bookmarkBusy = true
        self.bookmarkError = nil
        defer { self.bookmarkBusy = false }
        do {
            let response = try await self.bookmarkRepo.collectionSaveState(slug: self.slug)
            self.apply(response)
            self.bookmarkLoaded = true
        } catch {
            // This is an auxiliary capability check, not the source of truth
            // for whether the collection exists. Mark the check complete so a
            // missing/newer backend route cannot leave the header spinner
            // running forever or erase an already-loaded detail.
            self.bookmarkLoaded = true
            self.bookmarkError = tujiUserMessage(for: error)
        }
    }

    @discardableResult
    func save() async -> BookmarkChange? {
        guard !self.bookmarkBusy else { return nil }
        self.bookmarkBusy = true
        self.bookmarkError = nil
        self.bookmarkActionError = nil
        defer { self.bookmarkBusy = false }
        do {
            let response = try await self.bookmarkRepo.saveCollection(slug: self.slug)
            self.apply(response)
            self.bookmarkLoaded = true
            await self.reloadAccessIfLockChanged(saved: response.saved)
            return self.collection.map {
                BookmarkChange(collection: $0, isSaved: response.saved)
            }
        } catch {
            self.bookmarkError = tujiUserMessage(for: error)
            self.bookmarkActionError = tujiUserMessage(for: error)
            return nil
        }
    }

    @discardableResult
    func unsave() async -> BookmarkChange? {
        guard !self.bookmarkBusy else { return nil }
        self.bookmarkBusy = true
        self.bookmarkError = nil
        self.bookmarkActionError = nil
        defer { self.bookmarkBusy = false }
        do {
            let response = try await self.bookmarkRepo.unsaveCollection(slug: self.slug)
            self.apply(response)
            self.bookmarkLoaded = true
            await self.reloadAccessIfLockChanged(saved: response.saved)
            return self.collection.map {
                BookmarkChange(collection: $0, isSaved: response.saved)
            }
        } catch {
            self.bookmarkError = tujiUserMessage(for: error)
            self.bookmarkActionError = tujiUserMessage(for: error)
            return nil
        }
    }

    func dismissBookmarkActionError() {
        self.bookmarkActionError = nil
    }

    var remainingLearningCount: Int {
        max(0, self.totalCount - self.learningCount)
    }

    @discardableResult
    func learnRemaining() async -> Bool {
        guard self.unlocked, self.remainingLearningCount > 0, !self.learningBusy else {
            return false
        }
        self.learningBusy = true
        self.learningActionError = nil
        defer { self.learningBusy = false }
        do {
            let response = try await self.learningRepo.learnCollection(slug: self.slug)
            self.learningCount = response.learningCount
            self.totalCount = response.totalCount
            await self.learningRefresher.refreshAfterLearningMutation()
            return true
        } catch {
            self.learningActionError = tujiUserMessage(for: error)
            return false
        }
    }

    func dismissLearningActionError() {
        self.learningActionError = nil
    }

    private func apply(_ response: AtlasSaveResponse) {
        self.isSaved = response.saved
        self.collection = self.collection?.withSaveCount(response.saveCount)
    }

    /// 收藏 is what unlocks the member list, so a bookmark change is the one
    /// case where the detail *does* have to be re-read: `unlocked` only ever
    /// came from the server's `access`, and while a collection is locked the
    /// response carries a preview of the members rather than all of them — so
    /// flipping a local flag would open a list the screen does not have.
    /// Without this, saving left the screen showing 「收藏合集後查看全部 N 個內容」
    /// until the user backed out and came in again.
    ///
    /// Deliberately narrow: an owner is unlocked whatever their bookmark says,
    /// and a toggle that lands on the state we already have changes nothing, so
    /// neither costs a request.
    private func reloadAccessIfLockChanged(saved: Bool) async {
        guard !self.isOwner, self.unlocked != saved else { return }
        guard let response = try? await self.repo.collection(slug: self.slug) else { return }
        self.collection = response.collection
        self.items = response.items
        if let access = response.access {
            self.unlocked = access.unlocked
            self.totalCount = access.totalCount
            self.learningCount = access.learningCount
        }
    }

    private func matchesOwner(
        collection: AtlasCollection?,
        username: String?
    )
        -> Bool
    {
        guard let username, let handle = collection?.author?.handle else {
            return false
        }
        return username.caseInsensitiveCompare(handle) == .orderedSame
    }
}
