import Foundation
import Observation
import OSLog

@MainActor
@Observable
final class AtlasStore {
    static let shared = AtlasStore()

    private(set) var images: [AtlasImageSummary] = []
    private(set) var items: [AtlasItem] = []
    private(set) var cards: [AtlasCard] = []
    private(set) var cardStates: [String: AtlasCardState] = [:]
    private(set) var masteryByItemId: [String: AtlasMasteryEntry] = [:]
    private(set) var lastSyncAt: String?
    private(set) var loading = false
    private(set) var lastError: Error?

    private let repository: AtlasRepository
    private let log = Logger(subsystem: "app.tuji.ios", category: "atlas-store")

    private init(repository: AtlasRepository = LiveAtlasRepository.shared) {
        self.repository = repository
    }

    func sync(since: String? = nil, limit: Int = 500) async {
        self.loading = true
        self.lastError = nil
        defer { self.loading = false }

        do {
            let response = try await self.repository.sync(since: since ?? self.lastSyncAt, limit: limit)
            self.merge(response)
            self.lastSyncAt = response.serverTime
            self.log.info("atlas sync images=\(response.images.count, privacy: .public) items=\(response.items.count, privacy: .public)")
        } catch {
            self.lastError = error
            self.log.error("atlas sync failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    func uploadImage(
        data: Data,
        filename: String = "atlas.webp",
        mimeType: String = "image/webp",
        targetLanguage: String? = nil
    ) async throws -> AtlasUploadResponse {
        let response = try await self.repository.uploadImage(
            data: data,
            filename: filename,
            mimeType: mimeType,
            targetLanguage: targetLanguage
        )
        // Foreground updates local state only; the full reconciling sync is
        // deferred to AtlasCaptureQueue's background job.
        self.images = Self.merged(self.images, [response.image])
            .sorted { ($0.updatedAt ?? "") > ($1.updatedAt ?? "") }
        return response
    }

    func recognize(imageId: String, mode: String = "primary") async throws -> AtlasRecognitionResponse {
        try await self.repository.recognize(imageId: imageId, mode: mode)
    }

    func confirm(imageId: String, payload: AtlasConfirmPayload) async throws -> AtlasItem {
        let item = try await self.repository.confirm(imageId: imageId, payload: payload)
        self.items = Self.merged(self.items, [item])
            .sorted { ($0.updatedAt ?? "") > ($1.updatedAt ?? "") }
        return item
    }

    func createCards(itemId: String, cardTypes: [String] = ["image_recall", "flashcard"]) async throws -> [AtlasCard] {
        let cards = try await self.repository.createCards(itemId: itemId, cardTypes: cardTypes)
        self.cards = Self.merged(self.cards, cards)
            .sorted { ($0.updatedAt ?? "") > ($1.updatedAt ?? "") }
        return cards
    }

    func deleteImage(id: String) async throws {
        try await self.repository.deleteImage(id: id)
        self.images.removeAll { $0.id == id }
        self.items.removeAll { $0.imageId == id }
        self.cards.removeAll { $0.imageId == id }
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

    private func merge(_ response: AtlasSyncResponse) {
        self.images = Self.merged(self.images, response.images)
            .filter { $0.deletedAt == nil }
            .sorted { ($0.updatedAt ?? "") > ($1.updatedAt ?? "") }
        self.items = Self.merged(self.items, response.items)
            .filter { $0.deletedAt == nil }
            .sorted { ($0.updatedAt ?? "") > ($1.updatedAt ?? "") }
        self.cards = Self.merged(self.cards, response.cards)
            .filter { $0.deletedAt == nil }
            .sorted { ($0.updatedAt ?? "") > ($1.updatedAt ?? "") }
        for state in response.cardStates {
            self.cardStates[state.cardId] = state
        }
        for mastery in response.mastery {
            self.masteryByItemId[mastery.itemId] = mastery
        }
    }

    private static func merged<T: Identifiable>(_ current: [T], _ incoming: [T]) -> [T] where T.ID == String {
        var byId = Dictionary(uniqueKeysWithValues: current.map { ($0.id, $0) })
        for item in incoming {
            byId[item.id] = item
        }
        return Array(byId.values)
    }
}
