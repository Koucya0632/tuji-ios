// The 圖鑑管理 卡片 shelf: which captures are on screen, what state the shelf is
// in, and which rows are selected for deletion.
//
// All of this used to live across the three View structs in AtlasManageView,
// each with its own `@State private var store = AtlasStore.shared`: the
// learning-direction filter was written twice, the image→item join three times
// (a linear scan per row, inside `body`), and the empty/loading/hidden choice
// was an if-tree in the list. None of it could be reached by a test, and it hid
// two defects — a failed sync rendered as 「還沒有自製圖鑑卡片」, and a direction
// switch mid-selection left rows selected that were no longer on screen.
//
// Follows the screen view model convention (CONTEXT.md): the View is
// presentation-only and translates environment state into explicit inputs.

import Foundation
import Observation

/// One shelf row: an uploaded capture joined to its confirmed item, if the
/// pipeline has produced one yet.
struct AtlasShelfRow: Identifiable, Hashable {
    let image: AtlasImageSummary
    let item: AtlasItem?
    /// Set while 生成佇列 still has this capture in flight.
    ///
    /// It wins over the server row, because a job that is still running knows
    /// something the row it has not written yet cannot: this screen used to read
    /// 「已上傳」 off a photo the 卡片 grid was simultaneously calling 「生成中」.
    let inFlight: CaptureProgress?

    init(image: AtlasImageSummary, item: AtlasItem?, inFlight: CaptureProgress? = nil) {
        self.image = image
        self.item = item
        self.inFlight = inFlight
    }

    var id: String {
        self.image.id
    }

    /// The confirmed lemma once there is one; otherwise a title derived from the
    /// pipeline status, so it can never contradict the status shown beside it.
    var title: String {
        self.item?.lemma ?? self.image.placeholderTitle
    }

    var subtitle: String? {
        guard let zh = self.item?.displayZhHant, !zh.isEmpty else { return nil }
        return zh
    }

    var statusLabel: String {
        self.inFlight?.label ?? self.image.statusLabel
    }
}

/// What the shelf is showing. `failed` is the case the old if-tree never had.
enum AtlasShelfState: Equatable {
    case loading
    case loaded
    /// The sync failed and there is nothing cached to fall back on. Claiming
    /// 「還沒有卡片」 here reads as data loss to a user who owns cards.
    case failed
    /// Nothing in the current learning direction, but the user owns captures in
    /// the other one.
    case hiddenElsewhere(count: Int)
    case empty
}

/// What deleting a 圖鑑卡片 actually costs, in the only three kinds the warning
/// has to tell apart. Same shape and the same reasoning as
/// `CollectionDeleteWarning`: it is the last sentence an author reads before an
/// irreversible button, it makes three *different promises*, so it is a
/// decision rather than copy.
///
/// It matters more here than it does for a 合集, because this delete is the one
/// that reaches other accounts. `deleteAtlasImageCascade` is a hard DELETE: it
/// takes `atlas_public_items` and every saver's row with it, destroying review
/// progress that is not the author's to destroy. 取消公開 exists precisely so
/// that nobody has to walk down this path to unpublish something — which is why
/// the warning and that action belong on the same sheet.
enum AtlasItemDeleteWarning: Equatable {
    /// Never public and not in flight — nothing outside the account changes.
    case privateOnly
    /// In review. Deleting withdraws the submission before anyone sees it.
    case cancelsReview
    /// Live on 物見. It goes for everyone, and everyone who 收進'd it loses the
    /// progress they built on it.
    case takesDownFromPublic

    /// How much this promise costs, so a batch can take the heaviest one. The
    /// order is the case order; a batch that mixes a public row with private
    /// ones must speak for the public row, or the sentence is a lie about the
    /// most expensive thing the button is about to do.
    fileprivate var weight: Int {
        switch self {
        case .privateOnly: 0
        case .cancelsReview: 1
        case .takesDownFromPublic: 2
        }
    }
}

@MainActor
@Observable
final class AtlasShelfModel {
    /// 當前圖鑑語言, or nil before the View has said which one it is. The View
    /// pushes the environment's value in; the model never reaches `SettingsStore`.
    ///
    /// Optional because a `@State` model is constructed before SwiftUI can hand
    /// it the environment, and an unscoped shelf must not guess: this defaulted
    /// to `.ja`, so an 英文 learner's own cards were filtered against the language
    /// they are not learning until `onChange(initial:)` corrected it.
    var targetLanguage: TargetLanguage? {
        didSet {
            guard oldValue != self.targetLanguage else { return }
            self.reconcileSelection()
        }
    }

    private(set) var isSelecting = false
    private(set) var selectedIds: Set<String> = []
    private(set) var deleting = false
    private(set) var withdrawing = false
    private(set) var errorMessage: String?

    private let store: AtlasStore
    private let mutations: AtlasMutationRefreshing
    /// Read only for its in-flight jobs, so a row can say what the 卡片 grid is
    /// saying about the same photo.
    private let queue: AtlasCaptureQueue

    init(
        store: AtlasStore = .shared,
        mutations: AtlasMutationRefreshing = LiveAtlasMutationRefresher(),
        queue: AtlasCaptureQueue = .shared,
        targetLanguage: TargetLanguage? = nil
    ) {
        self.store = store
        self.mutations = mutations
        self.queue = queue
        self.targetLanguage = targetLanguage
    }

    // MARK: - Derived shelf

    /// Captures that teach the current target language, each joined to its item.
    /// An image with no confirmed item carries no language yet (未完成 / 生成中 /
    /// 失敗), so it stays visible in both directions. Empty until the shelf has
    /// been scoped — showing the wrong direction's cards is worse than showing
    /// none for the frame it takes the View to say which one it is.
    var rows: [AtlasShelfRow] {
        guard let scope = self.targetLanguage else { return [] }
        let inFlight = Dictionary(
            self.queue.jobs.map { ($0.imageId, $0.progress) },
            uniquingKeysWith: { first, _ in first }
        )
        return self.store.images.compactMap { image in
            let item = self.store.itemsByImageId[image.id]
            if let item, item.targetLanguage != scope { return nil }
            return AtlasShelfRow(image: image, item: item, inFlight: inFlight[image.id])
        }
    }

    /// Captures the direction filter is hiding — surfaced as a count so cards
    /// don't read as deleted after a direction switch.
    var hiddenCount: Int {
        self.store.images.count - self.rows.count
    }

    var state: AtlasShelfState {
        if !self.rows.isEmpty { return .loaded }
        // An unscoped shelf has no answer yet, and `empty` would claim one.
        if self.targetLanguage == nil { return .loading }
        if self.store.loading { return .loading }
        // Order matters: a failed sync leaves `images` empty, so without this
        // branch the shelf tells the user they own nothing.
        if self.store.lastError != nil { return .failed }
        let hidden = self.hiddenCount
        return hidden > 0 ? .hiddenElsewhere(count: hidden) : .empty
    }

    /// 選取 is offered only when there is something to select.
    var canSelect: Bool {
        !self.rows.isEmpty
    }

    func item(forImage imageId: String) -> AtlasItem? {
        self.store.itemsByImageId[imageId]
    }

    // MARK: - Load

    /// A full reconcile, not an incremental one: this screen is where a user
    /// checks that a capture actually landed.
    func load() async {
        await self.store.sync(.full)
        self.reconcileSelection()
    }

    // MARK: - Selection

    func setSelecting(_ selecting: Bool) {
        guard self.isSelecting != selecting else { return }
        self.isSelecting = selecting
        if !selecting {
            self.selectedIds.removeAll()
        }
    }

    func toggleSelection(_ id: String) {
        if self.selectedIds.contains(id) {
            self.selectedIds.remove(id)
        } else {
            self.selectedIds.insert(id)
        }
    }

    func isSelected(_ id: String) -> Bool {
        self.selectedIds.contains(id)
    }

    /// Drop ids that are no longer on the shelf. Without this a direction switch
    /// mid-selection leaves 「刪除 N 張卡片」 counting — and deleting — rows the
    /// user cannot see.
    private func reconcileSelection() {
        guard !self.selectedIds.isEmpty else { return }
        self.selectedIds.formIntersection(Set(self.rows.map(\.id)))
    }

    // MARK: - Delete

    /// Which promise the delete warning may make about this row.
    ///
    /// A row with no confirmed item has never been anywhere: an unconfirmed
    /// capture cannot have entered review, so it is `privateOnly` rather than a
    /// state we have to guess at.
    func deleteWarning(for row: AtlasShelfRow) -> AtlasItemDeleteWarning {
        guard let item = row.item else { return .privateOnly }
        switch item.review {
        case .pending, .pendingAuto, .pendingReview: return .cancelsReview
        case .approved: return .takesDownFromPublic
        case .draft, .rejected, .takedown, .withdrawn: return .privateOnly
        }
    }

    /// The promise a batch delete has to make: the heaviest one among the rows
    /// it would delete. Selection ids are resolved against the *visible* rows,
    /// the same set `delete(_:)` acts on.
    func deleteWarning(forSelected ids: Set<String>) -> AtlasItemDeleteWarning {
        self.rows
            .filter { ids.contains($0.id) }
            .map { self.deleteWarning(for: $0) }
            .max(by: { $0.weight < $1.weight }) ?? .privateOnly
    }

    /// Deletes every id even if one fails. The old path aborted on the first
    /// error and then cleared the selection, so the undeleted remainder was both
    /// invisible and unretryable; here only the rows that actually failed stay
    /// selected.
    func delete(_ ids: [String]) async {
        guard !ids.isEmpty, !self.deleting else { return }
        self.errorMessage = nil
        self.deleting = true
        defer { self.deleting = false }

        var failed: [String] = []
        var lastError: Error?
        for id in ids {
            do {
                try await self.store.deleteImage(id: id)
            } catch {
                failed.append(id)
                lastError = error
            }
        }

        self.selectedIds = Set(failed)
        if failed.isEmpty {
            self.isSelecting = false
        }
        self.errorMessage = lastError?.localizedDescription

        // Nothing moved server-side if every delete failed.
        if failed.count < ids.count {
            await self.mutations.refresh(after: .itemsDeleted)
        }
    }

    // MARK: - 取消公開

    /// The item stays, its cards stay, savers keep their progress — only the
    /// public row is retired. `AtlasStore.withdraw` re-syncs, so the 公開狀態 row
    /// reflects the server rather than a locally guessed status.
    ///
    /// `refreshing` is an explicit argument because the public-feed signal is a
    /// root-constructed environment value the model cannot reach on its own
    /// (ADR-0001) — the View supplies it, the same way it supplies
    /// `targetLanguage`.
    func withdraw(itemId: String, refreshing mutations: AtlasMutationRefreshing) async -> Bool {
        guard !self.withdrawing else { return false }
        self.withdrawing = true
        self.errorMessage = nil
        defer { self.withdrawing = false }
        do {
            try await self.store.withdraw(itemId: itemId)
            await mutations.refresh(after: .itemWithdrawn)
            return true
        } catch {
            self.errorMessage = tujiUserMessage(for: error)
            return false
        }
    }
}
