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

    // Raw is what the server sent; the published shelves are that minus the
    // blocked authors. Kept apart so a block applied while this screen is open
    // takes effect without a refetch, and so unblocking restores the rows the
    // fetch already paid for.
    private var exploreRaw = ShelfState(phase: .loading)
    private var savedRaw = ShelfState(phase: .idle)

    /// Blocked author handles, lowercased. An explicit input like every other
    /// piece of environment this model refuses to reach for itself.
    private var blockedAuthors: Set<String> = []

    var explore: ShelfState {
        self.hidingBlocked(self.exploreRaw)
    }

    var saved: ShelfState {
        self.hidingBlocked(self.savedRaw)
    }

    /// Re-apply the block list without refetching — the user can block from a
    /// pushed detail screen and pop straight back here.
    func applyBlocks(_ handles: Set<String>) {
        self.blockedAuthors = handles
    }

    private func hidingBlocked(_ state: ShelfState) -> ShelfState {
        guard !self.blockedAuthors.isEmpty else { return state }
        var copy = state
        copy.collections = state.collections.filter {
            guard let handle = $0.author?.handle else { return true }
            return !self.blockedAuthors.contains(handle.lowercased())
        }
        return copy
    }

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
        blockedAuthors: Set<String> = [],
        pendingExploreRefresh: Bool = false
    ) async {
        self.blockedAuthors = blockedAuthors
        if !isSignedIn {
            self.savedRaw = ShelfState(phase: .idle)
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
                self.savedRaw = ShelfState(phase: .idle)
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
        if let index = self.exploreRaw.collections.firstIndex(where: {
            $0.id == collection.id
        }) {
            self.exploreRaw.collections[index] = collection
        }

        guard collection.targetLanguage == language else { return }
        self.savedRaw.collections.removeAll { $0.id == collection.id }
        if isSaved {
            self.savedRaw.collections.insert(collection, at: 0)
        }
    }

    /// Profile editing returns the authoritative public identity before the
    /// public shelves are fetched again. Replace matching author snapshots in
    /// place so visible cards do not keep an old name or avatar until a pull to
    /// refresh.
    func applyAuthorIdentity(_ identity: AtlasAuthorRef) {
        self.exploreRaw.collections = Self.replacingAuthor(
            in: self.exploreRaw.collections,
            with: identity
        )
        self.savedRaw.collections = Self.replacingAuthor(
            in: self.savedRaw.collections,
            with: identity
        )
    }

    /// A plain appearance load re-triggers on every return from a detail. Skip it
    /// when a non-empty list for this language is already held and the load is not
    /// deliberate. This preserves the "don't clobber a good list on back" fix.
    /// `private`: it was internal with exactly one caller — the line below it in
    /// this same file — and zero test call sites. Interface surface opened for a
    /// test that was never written is the inverse of the `StudyLadder` lesson
    /// (*tests that must enter where the app does not*): here nothing entered at
    /// all. The rule it encodes is asserted through `update(_:)` and a request
    /// count instead.
    private func shouldSkipExploreLoad(language: TargetLanguage, force: Bool) -> Bool {
        !force
            && self.exploreRaw.loadedLanguage == language
            && !self.exploreRaw.collections.isEmpty
    }

    private func loadExplore(
        language: TargetLanguage,
        forceReload: Bool = false,
        pendingForce: Bool = false
    ) async {
        let force = forceReload || pendingForce
        if self.shouldSkipExploreLoad(language: language, force: force) { return }
        if !forceReload { self.exploreRaw.phase = .loading }
        do {
            self.exploreRaw.collections = try await self.exploreRepo.publicCollections(
                lang: language,
                forceReload: force
            )
            self.exploreRaw.loadedLanguage = language
            self.exploreRaw.phase = .ready
        } catch {
            if !forceReload { self.exploreRaw.collections = [] }
            self.exploreRaw.phase = .failed(error.localizedDescription)
        }
    }

    private func loadSaved(language: TargetLanguage, force: Bool = false) async {
        guard force
            || self.savedRaw.loadedLanguage != language
            || self.savedRaw.phase == .idle
        else {
            return
        }
        if self.savedRaw.loadedLanguage != language {
            self.savedRaw.collections = []
        }
        self.savedRaw.phase = .loading
        do {
            self.savedRaw.collections = try await self.savedRepo.savedCollections(lang: language)
            self.savedRaw.loadedLanguage = language
            self.savedRaw.phase = .ready
        } catch {
            self.savedRaw.loadedLanguage = language
            self.savedRaw.phase = .failed(error.localizedDescription)
        }
    }

    private static func replacingAuthor(
        in collections: [AtlasCollection],
        with identity: AtlasAuthorRef
    )
        -> [AtlasCollection]
    {
        collections.map { collection in
            guard collection.author?.handle == identity.handle else { return collection }
            return collection.withAuthor(identity)
        }
    }
}
