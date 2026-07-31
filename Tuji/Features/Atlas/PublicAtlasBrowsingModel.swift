// State module for AtlasPublicFeedView (公開圖鑑 browse). It owns both the public
// and saved shelves, including their language-scoped load state machines, refresh
// policy, authentication boundary, and confirmed bookmark reconciliation.
//
// The view translates SwiftUI environment values into explicit inputs. This model
// deliberately does not know about SettingsStore, AuthService,
// CommunityFeedRefresh, or CollectionBookmarkStore.

import Foundation
import Observation

@MainActor
@Observable
final class PublicAtlasBrowsingModel {
    enum Shelf: String, CaseIterable, Identifiable {
        case explore
        case saved

        var id: String {
            self.rawValue
        }
    }

    enum Phase: Equatable {
        case idle, loading, ready, failed(String)
    }

    struct ShelfState: Equatable {
        fileprivate(set) var collections: [AtlasCollection] = []
        fileprivate(set) var phase: Phase
        fileprivate(set) var loadedLanguage: TargetLanguage?

        var errorMessage: String? {
            if case let .failed(message) = self.phase { return message }
            return nil
        }
    }

    private(set) var explore = ShelfState(phase: .loading)
    private(set) var saved = ShelfState(phase: .idle)

    private let exploreRepo: CollectionsBrowsing
    private let savedRepo: CollectionBookmarking

    init(
        exploreRepo: CollectionsBrowsing = LiveAtlasRepository.shared,
        savedRepo: CollectionBookmarking = LiveAtlasRepository.shared
    ) {
        self.exploreRepo = exploreRepo
        self.savedRepo = savedRepo
    }

    /// Reconcile the screen's explicit context. The explore shelf is always kept
    /// warm; the private shelf loads only while selected and authenticated.
    func update(
        shelf: Shelf,
        language: TargetLanguage,
        isSignedIn: Bool,
        pendingExploreRefresh: Bool = false
    ) async {
        if !isSignedIn {
            self.saved = ShelfState(phase: .idle)
        }

        await self.loadExplore(
            language: language,
            pendingForce: pendingExploreRefresh
        )

        if shelf == .saved, isSignedIn {
            await self.loadSaved(language: language)
        }
    }

    /// Refresh the currently visible shelf without exposing each shelf's cache
    /// rules to the view.
    func refresh(
        shelf: Shelf,
        language: TargetLanguage,
        isSignedIn: Bool
    ) async {
        switch shelf {
        case .explore:
            await self.loadExplore(language: language, forceReload: true)
        case .saved:
            guard isSignedIn else {
                self.saved = ShelfState(phase: .idle)
                return
            }
            await self.loadSaved(language: language, force: true)
        }
    }

    func applyConfirmedBookmark(
        collection: AtlasCollection,
        isSaved: Bool,
        language: TargetLanguage
    ) {
        if let index = self.explore.collections.firstIndex(where: {
            $0.id == collection.id
        }) {
            self.explore.collections[index] = collection
        }

        guard collection.targetLanguage == language else { return }
        self.saved.collections.removeAll { $0.id == collection.id }
        if isSaved {
            self.saved.collections.insert(collection, at: 0)
        }
    }

    /// A plain appearance load re-triggers on every return from a detail. Skip it
    /// when a non-empty list for this language is already held and the load is not
    /// deliberate. This preserves the "don't clobber a good list on back" fix.
    func shouldSkipExploreLoad(language: TargetLanguage, force: Bool) -> Bool {
        !force
            && self.explore.loadedLanguage == language
            && !self.explore.collections.isEmpty
    }

    private func loadExplore(
        language: TargetLanguage,
        forceReload: Bool = false,
        pendingForce: Bool = false
    ) async {
        let force = forceReload || pendingForce
        if self.shouldSkipExploreLoad(language: language, force: force) { return }
        if !forceReload { self.explore.phase = .loading }
        do {
            self.explore.collections = try await self.exploreRepo.publicCollections(
                lang: language,
                forceReload: force
            )
            self.explore.loadedLanguage = language
            self.explore.phase = .ready
        } catch {
            if !forceReload { self.explore.collections = [] }
            self.explore.phase = .failed(error.localizedDescription)
        }
    }

    private func loadSaved(language: TargetLanguage, force: Bool = false) async {
        guard force
            || self.saved.loadedLanguage != language
            || self.saved.phase == .idle
        else {
            return
        }
        if self.saved.loadedLanguage != language {
            self.saved.collections = []
        }
        self.saved.phase = .loading
        do {
            self.saved.collections = try await self.savedRepo.savedCollections(lang: language)
            self.saved.loadedLanguage = language
            self.saved.phase = .ready
        } catch {
            self.saved.loadedLanguage = language
            self.saved.phase = .failed(error.localizedDescription)
        }
    }
}
