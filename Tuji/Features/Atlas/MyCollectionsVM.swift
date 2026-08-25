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

/// What deleting a 合集 actually costs, in the only three kinds the warning has
/// to tell apart. It is the last sentence an author reads before an irreversible
/// button, and it makes three *different promises* — so it is a decision, not
/// copy, and it lived as a `private func` on a `View` where nothing could reach
/// it. The screen still owns the sentences (`TodayDecisions` / `TodayView`
/// split); this owns which one is true.
enum CollectionDeleteWarning: Equatable {
    /// In review. Deleting withdraws the submission before it is ever seen.
    case cancelsReview
    /// Live on 物見. Deleting takes it down for everyone, immediately.
    case takesDownFromPublic
    /// Never public and not in flight — nothing outside the account changes.
    case privateOnly
}

@MainActor
@Observable
final class MyCollectionsVM {
    private(set) var loading = true
    private(set) var loadError: String?

    /// The in-flight and failed states of a delete, here rather than on the
    /// `View` for the reason PR #178 gave when it moved 刪除帳號 and 清除進度 out
    /// of 設定: a destructive write whose guard, error and consequences live in
    /// a `View` body is a destructive write no test can reach.
    private(set) var deleting = false
    private(set) var deleteError: String?

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

    /// Which promise the delete warning may make about this collection.
    func deleteWarning(for collection: AtlasMyCollection) -> CollectionDeleteWarning {
        switch collection.review {
        case .pending, .pendingAuto, .pendingReview: .cancelsReview
        case .approved: .takesDownFromPublic
        case .draft, .rejected, .takedown, .withdrawn: .privateOnly
        }
    }

    /// Delete one 合集, and refresh whatever that changed.
    ///
    /// Takes the collection rather than its id because `wasPublic` is a property
    /// of the row, not something the caller should be re-deriving — the `View`
    /// spelled it `collection.review == .approved` inline, three lines away from
    /// `deleteMessage` making the same distinction in different words.
    ///
    /// Non-throwing, like `SettingsVM`'s two: the failure has exactly one
    /// destination (`deleteError`), and a `throws` that every caller must
    /// remember to catch into the same property is a rule stated at the call
    /// site instead of here. The cache is only touched after the server agrees —
    /// a row that vanishes from a list on a failed delete is a lie the next
    /// refresh silently corrects.
    func delete(
        _ collection: AtlasMyCollection,
        refreshing: AtlasMutationRefreshing
    ) async {
        guard !self.deleting else { return }
        self.deleting = true
        self.deleteError = nil
        defer { self.deleting = false }
        let wasPublic = collection.review == .approved
        do {
            try await self.repo.deleteCollection(id: collection.id)
            self.cache.remove(id: collection.id)
            await refreshing.refresh(after: .collectionDeleted(wasPublic: wasPublic))
        } catch {
            self.deleteError = tujiUserMessage(for: error)
        }
    }
}
