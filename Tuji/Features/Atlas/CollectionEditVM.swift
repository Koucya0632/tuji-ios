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
    /// Shared error line for meta-save and member edits; a failed publish takes
    /// precedence (see `errorMessage`).
    private(set) var actionError: String?
    /// The two fields the view binds and edits directly.
    var title = ""
    var description = ""

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

    /// 儲存 is enabled when not mid-save and the title isn't blank.
    var canSaveMeta: Bool {
        !self.savingMeta && !self.trimmedTitle.isEmpty
    }

    /// The single error line the edit screen shows — a failed publish wins over a
    /// stale meta/member edit error.
    var errorMessage: String? {
        if case let .failed(message) = self.submitState { return message }
        return self.actionError
    }

    /// The member picker is scoped to this collection's language.
    var language: TargetLanguage {
        self.collection?.targetLanguage ?? .ja
    }

    private var trimmedTitle: String {
        self.title.trimmingCharacters(in: .whitespaces)
    }

    private var trimmedDescription: String? {
        let trimmed = self.description.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? nil : trimmed
    }

    // MARK: - Load

    func load() async {
        self.phase = .loading
        do {
            let response = try await self.repo.collectionEdit(id: self.collectionId)
            self.collection = response.collection
            self.members = response.items
            self.title = response.collection.title
            self.description = response.collection.description ?? ""
            self.coverId = response.collection.coverPublicItemId ?? response.items.first?.publicItemId
            self.avatarColor = response.collection.avatarColor
            self.avatarPreviewURL = response.collection.avatarPreviewURL
            self.phase = .ready
        } catch {
            // Keep any already-loaded collection on screen; only a first load with
            // nothing to show surfaces the full error state.
            self.phase = .failed(error.localizedDescription)
        }
    }

    // MARK: - Meta

    func saveMeta() async {
        guard !self.savingMeta else { return }
        self.savingMeta = true
        self.metaSaved = false
        self.actionError = nil
        do {
            try await self.repo.updateCollection(
                id: self.collectionId,
                title: self.trimmedTitle,
                description: self.trimmedDescription,
                coverPublicItemId: self.coverId
            )
            self.metaSaved = true
        } catch {
            self.actionError = error.localizedDescription
        }
        self.savingMeta = false
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
            self.actionError = error.localizedDescription
            return nil
        }
    }

    // MARK: - Members

    func addMember(_ publicItemId: String) async {
        do {
            try await self.repo.addCollectionItem(id: self.collectionId, publicItemId: publicItemId)
            await self.reloadMembers()
        } catch {
            self.actionError = error.localizedDescription
        }
    }

    func removeMember(_ publicItemId: String) async {
        do {
            try await self.repo.removeCollectionItem(id: self.collectionId, publicItemId: publicItemId)
            if self.members.first(where: { $0.id == publicItemId })?.publicItemId == self.coverId {
                self.coverId = nil
            }
            await self.reloadMembers()
        } catch {
            self.actionError = error.localizedDescription
        }
    }

    private func reloadMembers() async {
        do {
            let response = try await self.repo.collectionEdit(id: self.collectionId)
            self.members = response.items
            if self.coverId == nil { self.coverId = response.items.first?.publicItemId }
        } catch {
            self.actionError = error.localizedDescription
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
            try await self.repo.updateCollection(
                id: self.collectionId,
                title: self.trimmedTitle,
                description: self.trimmedDescription,
                coverPublicItemId: self.coverId
            )
            let response = try await self.repo.publishCollection(id: self.collectionId)
            self.submitState = .done(response.moderation)
            await self.load()
            return response.moderation?.published == true
        } catch {
            self.submitState = .failed(error.localizedDescription)
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
            self.actionError = error.localizedDescription
            return false
        }
    }
}
