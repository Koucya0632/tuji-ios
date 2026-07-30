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

    private let repo: CollectionDetailReading
    private let bookmarkRepo: CollectionBookmarking

    init(
        slug: String,
        preview: AtlasCollection? = nil,
        repo: CollectionDetailReading = LiveAtlasRepository.shared,
        bookmarkRepo: CollectionBookmarking = LiveAtlasRepository.shared
    ) {
        self.slug = slug
        self.collection = preview
        self.repo = repo
        self.bookmarkRepo = bookmarkRepo
    }

    var errorMessage: String? {
        if case let .failed(message) = self.phase { return message }
        return nil
    }

    func load() async {
        self.phase = .loading
        self.isUnavailable = false
        do {
            let response = try await self.repo.collection(slug: self.slug)
            self.collection = response.collection
            self.items = response.items
            self.phase = .ready
        } catch {
            if case APIError.notFound = error {
                self.collection = nil
                self.items = []
                self.isUnavailable = true
            }
            // Keep any preview header on screen; the error state shows only when
            // there's nothing to render.
            self.phase = .failed(error.localizedDescription)
        }
    }

    func loadBookmarkState() async {
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
            self.bookmarkError = error.localizedDescription
        }
    }

    @discardableResult
    func save() async -> AtlasCollection? {
        guard !self.bookmarkBusy else { return nil }
        self.bookmarkBusy = true
        self.bookmarkError = nil
        self.bookmarkActionError = nil
        defer { self.bookmarkBusy = false }
        do {
            let response = try await self.bookmarkRepo.saveCollection(slug: self.slug)
            self.apply(response)
            self.bookmarkLoaded = true
            return self.collection
        } catch {
            self.bookmarkError = error.localizedDescription
            self.bookmarkActionError = error.localizedDescription
            return nil
        }
    }

    @discardableResult
    func unsave() async -> AtlasCollection? {
        guard !self.bookmarkBusy else { return nil }
        self.bookmarkBusy = true
        self.bookmarkError = nil
        self.bookmarkActionError = nil
        defer { self.bookmarkBusy = false }
        do {
            let response = try await self.bookmarkRepo.unsaveCollection(slug: self.slug)
            self.apply(response)
            self.bookmarkLoaded = true
            return self.collection
        } catch {
            self.bookmarkError = error.localizedDescription
            self.bookmarkActionError = error.localizedDescription
            return nil
        }
    }

    func dismissBookmarkActionError() {
        self.bookmarkActionError = nil
    }

    private func apply(_ response: AtlasSaveResponse) {
        self.isSaved = response.saved
        self.collection = self.collection?.withSaveCount(response.saveCount)
    }
}
