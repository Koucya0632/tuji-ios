import Foundation
import Observation
import OSLog

/// How much of the server's atlas a sync asks for. `since: nil` used to be the
/// only way to say "everything", but it fell through to the stored cursor, so
/// every caller that wanted a full reconcile silently got an incremental one.
enum AtlasSyncScope {
    /// Rows changed since the last successful sync. Cheap; the default.
    case incremental
    /// Every row the account owns, ignoring the stored cursor. What a caller
    /// wants after a mutation whose server-side effects reach rows the cursor
    /// would skip (a fresh capture, a manage-screen appearance).
    case full
}

@MainActor
@Observable
final class AtlasStore {
    static let shared = AtlasStore()

    private(set) var images: [AtlasImageSummary] = []
    private(set) var items: [AtlasItem] = []
    /// `items` keyed by the image that produced them. The manage shelf joins on
    /// this once per row; the three view structs that used to do it each ran a
    /// linear scan inside `body`, making the list render O(n²).
    private(set) var itemsByImageId: [String: AtlasItem] = [:]
    private(set) var entitlement: AtlasEntitlement?
    private(set) var loading = false
    private(set) var lastError: Error?

    private var lastSyncAt: String?
    private let repository: AtlasAuthoring
    private let log = Logger(subsystem: "app.tuji.ios", category: "atlas-store")

    /// Bumped by `reset()`. Requests capture it before awaiting and drop their
    /// response if it changed, so a request racing a sign-out can't repopulate
    /// the store with the previous account's data.
    private var generation = 0

    /// Not private: the `AtlasAuthoring` seam only pays for itself if a test can
    /// stand this store up over a fake. Production still goes through `.shared`
    /// (ADR-0001 — the lifecycle singletons stay).
    init(repository: AtlasAuthoring = LiveAtlasRepository.shared) {
        self.repository = repository
    }

    /// Wipe all account-scoped state. Called on sign-out: this singleton lives
    /// for the app's lifetime and `merge` is additive, so without this the
    /// previous account's 自製圖鑑 (and its stale incremental cursor)
    /// would survive into the next account's session.
    func reset() {
        self.generation += 1
        self.images = []
        self.items = []
        self.itemsByImageId = [:]
        self.entitlement = nil
        self.lastSyncAt = nil
        self.lastError = nil
    }

    func sync(_ scope: AtlasSyncScope = .incremental, limit: Int = 500) async {
        self.loading = true
        self.lastError = nil
        defer { self.loading = false }

        let generation = self.generation
        do {
            let since = scope == .full ? nil : self.lastSyncAt
            let response = try await self.repository.sync(since: since, limit: limit)
            guard generation == self.generation else { return }
            self.merge(response)
            self.lastSyncAt = response.serverTime
            self.log
                .info(
                    "atlas sync images=\(response.images.count, privacy: .public) items=\(response.items.count, privacy: .public)"
                )
        } catch {
            guard generation == self.generation else { return }
            self.lastError = error
            self.log.error("atlas sync failed: \(error.localizedDescription, privacy: .public)")
        }
        await self.refreshEntitlement()
    }

    /// Pull the current tier / limits / usage. Best-effort — a failure leaves the
    /// last snapshot in place and never surfaces as `lastError`, so quota UI
    /// degrades to "unknown" (permissive) rather than blocking the flow.
    func refreshEntitlement() async {
        let generation = self.generation
        do {
            let entitlement = try await self.repository.entitlement()
            guard generation == self.generation else { return }
            self.entitlement = entitlement
        } catch {
            self.log.error("atlas entitlement fetch failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    func uploadImage(
        data: Data,
        filename: String = "atlas.webp",
        mimeType: String = "image/webp",
        targetLanguage: TargetLanguage? = nil
    ) async throws
        -> AtlasUploadResponse
    {
        let generation = self.generation
        let response = try await self.repository.uploadImage(
            data: data,
            filename: filename,
            mimeType: mimeType,
            targetLanguage: targetLanguage
        )
        guard generation == self.generation else { return response }
        // Foreground updates local state only; the full reconciling sync is
        // deferred to AtlasCaptureQueue's background job.
        self.images = Self.sortedByRecency(Self.merged(self.images, [response.image]))
        return response
    }

    func recognize(imageId: String, mode: AtlasRecognitionMode = .primary) async throws -> AtlasRecognitionResponse {
        try await self.repository.recognize(imageId: imageId, mode: mode)
    }

    func confirm(imageId: String, payload: AtlasConfirmPayload) async throws -> AtlasItem {
        let generation = self.generation
        let item = try await self.repository.confirm(imageId: imageId, payload: payload)
        guard generation == self.generation else { return item }
        self.setItems(Self.merged(self.items, [item]))
        return item
    }

    /// The created cards are the server's receipt, not state this store keeps —
    /// nothing in the app reads a card list, and the queue discards the return.
    func createCards(itemId: String, cardTypes: [String] = ["image_recall", "flashcard"]) async throws -> [AtlasCard] {
        try await self.repository.createCards(itemId: itemId, cardTypes: cardTypes)
    }

    func deleteImage(id: String) async throws {
        let generation = self.generation
        try await self.repository.deleteImage(id: id)
        // Same sign-out fence as every other mutation: without it a delete that
        // lands after `reset()` mutates the next account's (empty) shelf.
        guard generation == self.generation else { return }
        self.images.removeAll { $0.id == id }
        self.setItems(self.items.filter { $0.imageId != id })
    }

    /// Kick off (or re-run) AI enrichment for a custom item — fills
    /// definition / synonyms / forms / etymology so its detail page matches a
    /// dictionary word. itemId is the bare UUID (no "atlas:" prefix).
    func enrich(itemId: String) async throws {
        try await self.repository.enrich(itemId: itemId)
    }

    /// Full per-word detail for a custom item (same `Word` shape as the
    /// dictionary), lazily enriched server-side on first fetch.
    func detail(itemId: String) async throws -> Word {
        try await self.repository.detail(itemId: itemId)
    }

    /// 取消公開. The withdraw response carries no item (the row is the server's
    /// to describe), so refresh from sync rather than patching a status in
    /// locally and risking a stale 已公開 badge on a card that is no longer up.
    func withdraw(itemId: String) async throws {
        _ = try await self.repository.withdraw(itemId: itemId)
        await self.sync()
    }

    private func merge(_ response: AtlasSyncResponse) {
        self.images = Self.sortedByRecency(Self.merged(self.images, response.images))
            .filter { $0.deletedAt == nil }
        self.setItems(Self.merged(self.items, response.items).filter { $0.deletedAt == nil })
    }

    /// The single place `items` and its by-image index move together.
    private func setItems(_ items: [AtlasItem]) {
        self.items = Self.sortedByRecency(items)
        // Sorted newest-first, so on the (server-side impossible) chance two
        // items claim one image, the newer one wins the row.
        self.itemsByImageId = Dictionary(self.items.map { ($0.imageId, $0) }) { newer, _ in newer }
    }

    private static func sortedByRecency<T: HasUpdatedAt>(_ values: [T]) -> [T] {
        values.sorted { ($0.updatedAt ?? "") > ($1.updatedAt ?? "") }
    }

    private static func merged<T: Identifiable>(_ current: [T], _ incoming: [T]) -> [T] where T.ID == String {
        var byId = Dictionary(uniqueKeysWithValues: current.map { ($0.id, $0) })
        for item in incoming {
            byId[item.id] = item
        }
        return Array(byId.values)
    }
}

/// Lets the store sort images and items through one helper instead of repeating
/// the `updatedAt` comparator at every merge site.
protocol HasUpdatedAt {
    var updatedAt: String? { get }
}

extension AtlasImageSummary: HasUpdatedAt {}
extension AtlasItem: HasUpdatedAt {}
