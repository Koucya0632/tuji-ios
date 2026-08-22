// View model for AtlasMyCollectionsView (我的合集 — the author's own collections
// list). Owns the load state behind the CollectionManaging seam so the view is
// presentation-only and the load/error transitions are unit-testable.

import Foundation
import Observation

/// The rows outlive the screen that shows them. 圖鑑管理 is somewhere a user
/// leaves and comes back to, and the VM is `@State` on a view SwiftUI throws
/// away on pop — so a view-scoped list meant every single return started from
/// an empty list and a spinner, re-answering a question answered seconds ago.
/// 圖鑑卡片 never did that, because it reads the app-lifetime `AtlasStore`.
///
/// Account-scoped, and this lives as long as the process does: `reset()` runs
/// on sign-out beside `AtlasStore.reset()`, or the next account inherits these.
@MainActor
@Observable
final class MyCollectionsCache {
    static let shared = MyCollectionsCache()

    private(set) var collections: [AtlasMyCollection] = []

    /// Not private: a test that shares `.shared` would leak rows into the next
    /// test. Every test stands up its own.
    init() {}

    func replace(_ collections: [AtlasMyCollection]) {
        self.collections = collections
    }

    func prepend(_ collection: AtlasMyCollection) {
        self.collections.removeAll { $0.id == collection.id }
        self.collections.insert(collection, at: 0)
    }

    func remove(id: String) {
        self.collections.removeAll { $0.id == id }
    }

    func reset() {
        self.collections = []
    }
}

@MainActor
@Observable
final class MyCollectionsVM {
    private(set) var loading = true
    private(set) var loadError: String?

    private let repo: CollectionManaging
    private let cache: MyCollectionsCache

    /// Coming back from 編輯合集 fires two refreshes in the same frame — the
    /// list's `.task` restarts (NavigationStack tore the list down while it was
    /// covered) *and* the edit screen's `onDisappear` asks for a reload. Both
    /// want the same thing, so the second one rides along with the first
    /// instead of running a second request and blinking the list again.
    private var inFlight = false

    init(
        repo: CollectionManaging = LiveAtlasRepository.shared,
        cache: MyCollectionsCache = .shared
    ) {
        self.repo = repo
        self.cache = cache
    }

    var collections: [AtlasMyCollection] {
        self.cache.collections
    }

    /// Whether the screen has nothing to show yet. A reload with rows already
    /// on screen is a refresh, not a cold start: it must not swap them for a
    /// spinner (same rule as `AtlasShelfModel.state`, where `.loaded` wins).
    /// With the cache warm this is false on the very first frame, so a return
    /// visit renders the last known rows and refreshes behind them.
    var showsPlaceholder: Bool {
        self.loading && self.collections.isEmpty
    }

    func load() async {
        guard !self.inFlight else { return }
        self.inFlight = true
        defer { self.inFlight = false }
        self.loading = true
        self.loadError = nil
        do {
            let collections = try await self.repo.myCollections()
            self.cache.replace(collections)
        } catch {
            self.loadError = tujiUserMessage(for: error)
        }
        self.loading = false
    }

    func collections(for language: TargetLanguage) -> [AtlasMyCollection] {
        self.collections.filter { $0.targetLanguage == language }
    }

    func prepend(_ collection: AtlasMyCollection) {
        self.cache.prepend(collection)
    }

    func delete(id: String) async throws {
        try await self.repo.deleteCollection(id: id)
        self.cache.remove(id: id)
    }
}
