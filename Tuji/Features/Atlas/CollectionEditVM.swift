// View model for AtlasCollectionEditView (編輯合集). Owns the whole
// load → 校正 meta → 挑選成員 → 送審 state machine so the view stays
// presentation-only and the order-sensitive submit() (persist the meta BEFORE
// the publish gate reads the stored row) is a plain, unit-testable method behind
// the CollectionEditing seam. Mirrors the AtlasCaptureVM pattern.

import Foundation
import Observation

@MainActor
@Observable
final class CollectionEditVM {
    /// Full-screen phase while `collection` is still nil. Once it's set, the view
    /// keeps showing content even across a later reloading/failed phase.
    enum Phase: Equatable {
        case loading, ready, failed(String)
    }

    /// Publish lifecycle. `.done` carries the machine-gate outcome so the view can
    /// show the right 已送出 / 已通過 copy; the VM deliberately never reaches the
    /// global feed-refresh center — `submit()` returns whether it published and the
    /// view decides.
    enum SubmitState: Equatable {
        case idle
        case submitting
        case done(AtlasPublishModeration?)
        case failed(String)
    }

    let collectionId: String

    private(set) var collection: AtlasCollectionEdit?
    private(set) var members: [AtlasPublicItem] = []
    private(set) var coverId: String?
    private(set) var avatarColor: String?
    private(set) var avatarPreviewURL: URL?
    private(set) var uploadingAvatar = false
    private(set) var phase: Phase = .loading
    private(set) var savingMeta = false
    private(set) var metaSaved = false
    private(set) var submitState: SubmitState = .idle
    private(set) var withdrawing = false
    /// Shared error line for meta-save and avatar upload; a failed publish takes
    /// precedence (see `errorMessage`).
    private(set) var actionError: String?
    /// 加入/移除卡片 failures, kept apart from `actionError` so the refusal can be
    /// drawn beside the rows it is about. Folded into the page-level
    /// `errorMessage` it landed at the bottom of the screen — which, now that the
    /// members are full rows rather than a three-up grid, can be a screenful and
    /// a half below the ✕ that was tapped.
    private(set) var memberError: String?
    /// The two fields the view binds and edits directly.
    var title = ""
    var description = ""
    /// What the server last confirmed for those two fields — exactly the values
    /// a save would send. 儲存 is lit by the difference between these and what is
    /// typed, so a screen nobody has touched cannot offer to save itself.
    private var savedTitle = ""
    private var savedDescription: String?

    private let repo: CollectionEditing

    init(collectionId: String, repo: CollectionEditing = LiveAtlasRepository.shared) {
        self.collectionId = collectionId
        self.repo = repo
    }

    // MARK: - Derived

    /// 公開合集 is enabled only when no submit is in flight and the collection has
    /// at least one member (the server rejects an empty collection anyway).
    var canSubmit: Bool {
        if case .submitting = self.submitState { return false }
        guard self.collection?.review.canSubmit ?? true else { return false }
        return !self.members.isEmpty
    }

    /// 取消公開 shows only for a collection that is actually on the browse feed.
    var canWithdraw: Bool {
        !self.withdrawing && (self.collection?.review.canWithdraw ?? false)
    }

    var isSubmitting: Bool {
        if case .submitting = self.submitState { return true }
        return false
    }

    var unpublishedMemberCount: Int {
        self.members.count { $0.publicationState != "public" }
    }

    /// 標題/簡介 differ from what the server last confirmed. Compared trimmed on
    /// both sides, so trailing whitespace alone is not an edit — and read by the
    /// back button, which asks before dropping real ones.
    var isMetaDirty: Bool {
        self.trimmedTitle != self.savedTitle || self.trimmedDescription != self.savedDescription
    }

    /// 儲存 is enabled when not mid-save, the title isn't blank, and something
    /// actually changed. Without the last clause the action is lit on a screen
    /// that has nothing to write, which is what made it read as the page's
    /// primary button rather than as one field's commit.
    var canSaveMeta: Bool {
        !self.savingMeta && !self.trimmedTitle.isEmpty && self.isMetaDirty
    }

    /// The single error line the edit screen shows — a failed publish wins over a
    /// stale meta/member edit error.
    var errorMessage: String? {
        if case let .failed(message) = self.submitState { return message }
        return self.actionError
    }

    private var trimmedTitle: String {
        self.title.trimmingCharacters(in: .whitespaces)
    }

    private var trimmedDescription: String? {
        // whitespacesAndNewlines, not whitespaces: 簡介 is a multiline field, so a
        // stray trailing newline is reachable and must not count as content.
        let trimmed = self.description.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    // MARK: - Load

    func load() async {
        self.phase = .loading
        do {
            let response = try await self.repo.collectionEdit(id: self.collectionId)
            // Asked before anything is overwritten: `submit()` and `withdraw()`
            // both reload, and a reload that reseeds the form would silently drop
            // text the user has typed but not saved — right after the back button
            // has promised to ask before doing exactly that.
            let keepsTypedMeta = self.isMetaDirty
            self.collection = response.collection
            self.members = response.items
            if !keepsTypedMeta {
                self.title = response.collection.title
                self.description = response.collection.description ?? ""
                self.savedTitle = self.trimmedTitle
                self.savedDescription = self.trimmedDescription
                // Otherwise 已儲存 reappears after a publish reload, beside the
                // 已送出 line, with nothing having been saved.
                self.metaSaved = false
            }
            self.coverId = response.collection.coverPublicItemId ?? response.items.first?.publicItemId
            self.avatarColor = response.collection.avatarColor
            self.avatarPreviewURL = response.collection.avatarPreviewURL
            self.phase = .ready
        } catch {
            // Keep any already-loaded collection on screen; only a first load with
            // nothing to show surfaces the full error state.
            self.phase = .failed(tujiUserMessage(for: error))
        }
    }

    // MARK: - Meta

    /// Returns whether the write landed, so 儲存並離開 only leaves the screen on
    /// a save that actually happened.
    @discardableResult
    func saveMeta() async -> Bool {
        guard !self.savingMeta else { return false }
        // Read once, up front: these are what goes to the server, so they are
        // also what the baseline becomes. Re-reading them after the round trip
        // would bank text the user typed *while* it was in flight and leave
        // 儲存 dark over unsaved edits.
        let title = self.trimmedTitle
        let description = self.trimmedDescription
        self.savingMeta = true
        self.metaSaved = false
        self.actionError = nil
        do {
            try await self.repo.updateCollection(
                id: self.collectionId,
                title: title,
                description: description,
                coverPublicItemId: self.coverId
            )
            self.savedTitle = title
            self.savedDescription = description
            self.metaSaved = true
        } catch {
            self.actionError = tujiUserMessage(for: error)
        }
        self.savingMeta = false
        return self.metaSaved
    }

    /// Uploads one already-confirmed square crop. The public avatar image and
    /// its fallback color move together; any error deliberately leaves
    /// the previously loaded identity untouched.
    @discardableResult
    func updateAvatar(_ imageData: Data) async -> String? {
        guard !self.uploadingAvatar else { return nil }
        self.uploadingAvatar = true
        self.actionError = nil
        defer { self.uploadingAvatar = false }
        do {
            let response = try await self.repo.updateCollectionAvatar(
                id: self.collectionId,
                imageData: imageData
            )
            self.avatarColor = response.avatarColor
            self.avatarPreviewURL = URL(string: response.avatarPreviewUrl ?? response.avatarImageUrl)
            return response.avatarColor
        } catch {
            self.actionError = tujiUserMessage(for: error)
            return nil
        }
    }

    // MARK: - Members

    /// Returns nil when the server took the item, otherwise the sentence to
    /// show — the picker un-ticks the tile it optimistically ticked *and* says
    /// why. Swallowing the failure into `actionError` alone left the picker
    /// showing a ✓ for an item that was never added; returning only `false`
    /// left it showing 「加入失敗，請再試一次。」 over a refusal that no amount
    /// of retrying would clear (a 合集 that is already public cannot take an
    /// unpublished item — see `CollectionCandidatesModel`).
    ///
    /// `actionError` is still set, so the reason is also there on the screen
    /// underneath once the sheet closes.
    @discardableResult
    func addMember(_ publicItemId: String) async -> String? {
        do {
            self.memberError = nil
            try await self.repo.addCollectionItem(id: self.collectionId, publicItemId: publicItemId)
            await self.reloadMembers()
            return nil
        } catch {
            let message = tujiUserMessage(for: error)
            self.memberError = message
            return message
        }
    }

    func removeMember(_ publicItemId: String) async {
        do {
            self.memberError = nil
            try await self.repo.removeCollectionItem(id: self.collectionId, publicItemId: publicItemId)
            if self.members.first(where: { $0.id == publicItemId })?.publicItemId == self.coverId {
                self.coverId = nil
            }
            await self.reloadMembers()
        } catch {
            self.memberError = tujiUserMessage(for: error)
        }
    }

    /// Members only — deliberately not `load()`, which would reseed 標題/簡介 and
    /// take the user's unsaved text with it on every add and remove.
    private func reloadMembers() async {
        do {
            let response = try await self.repo.collectionEdit(id: self.collectionId)
            self.members = response.items
            if self.coverId == nil { self.coverId = response.items.first?.publicItemId }
        } catch {
            self.memberError = tujiUserMessage(for: error)
        }
    }

    // MARK: - Submit

    /// Persist the latest 標題/簡介/封面 BEFORE publishing, because the machine gate
    /// reads the stored row. Returns `true` iff the gate auto-published, so the
    /// caller can mark the public feed stale — keeping the VM free of the global
    /// refresh center and unit-testable.
    @discardableResult
    func submit() async -> Bool {
        guard !self.isSubmitting, !self.members.isEmpty else { return false }
        self.submitState = .submitting
        self.actionError = nil
        do {
            let title = self.trimmedTitle
            let description = self.trimmedDescription
            try await self.repo.updateCollection(
                id: self.collectionId,
                title: title,
                description: description,
                coverPublicItemId: self.coverId
            )
            // Banked here rather than left to the reload below: `load()` can fail,
            // and then 儲存 would stay lit over text the server already has.
            self.savedTitle = title
            self.savedDescription = description
            let response = try await self.repo.publishCollection(id: self.collectionId)
            self.submitState = .done(response.moderation)
            await self.load()
            return response.moderation?.published == true
        } catch {
            self.submitState = .failed(tujiUserMessage(for: error))
            return false
        }
    }

    /// 取消公開 — takes the collection off the browse feed. Members stay
    /// published: this retires the shelf, not the photos on it.
    ///
    /// Returns true on success so the view can mark the public feed stale;
    /// like `submit()`, the VM never reaches the shared refresh center itself.
    @discardableResult
    func withdraw() async -> Bool {
        guard self.canWithdraw else { return false }
        self.withdrawing = true
        self.actionError = nil
        self.submitState = .idle
        defer { self.withdrawing = false }
        do {
            _ = try await self.repo.withdrawCollection(id: self.collectionId)
            await self.load()
            return true
        } catch {
            self.actionError = tujiUserMessage(for: error)
            return false
        }
    }
}
