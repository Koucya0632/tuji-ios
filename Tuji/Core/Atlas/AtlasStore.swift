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

    private let log = Logger(subsystem: "app.tuji.ios", category: "atlas-store")

    private init() {}

    func sync(since: String? = nil, limit: Int = 500) async {
        self.loading = true
        self.lastError = nil
        defer { self.loading = false }

        do {
            let response: AtlasSyncResponse = try await APIClient.shared.get(
                .atlasSync(since: since ?? self.lastSyncAt, limit: limit)
            )
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
        var fields: [String: String] = [:]
        if let targetLanguage {
            fields["targetLanguage"] = targetLanguage
        }
        let response: AtlasUploadResponse = try await APIClient.shared.upload(
            .atlasImages(limit: 30),
            fileField: "file",
            filename: filename,
            mimeType: mimeType,
            data: data,
            fields: fields
        )
        // Foreground updates local state only; the full reconciling sync is
        // deferred to AtlasCaptureQueue's background job.
        self.images = Self.merged(self.images, [response.image])
            .sorted { ($0.updatedAt ?? "") > ($1.updatedAt ?? "") }
        return response
    }

    func recognize(imageId: String, mode: String = "primary") async throws -> AtlasRecognitionResponse {
        struct Payload: Encodable { let mode: String }
        return try await APIClient.shared.post(
            .atlasImageRecognize(id: imageId),
            body: Payload(mode: mode)
        )
    }

    func confirm(imageId: String, payload: AtlasConfirmPayload) async throws -> AtlasItem {
        let response: AtlasItemResponse = try await APIClient.shared.post(
            .atlasImageConfirm(id: imageId),
            body: payload
        )
        self.items = Self.merged(self.items, [response.item])
            .sorted { ($0.updatedAt ?? "") > ($1.updatedAt ?? "") }
        return response.item
    }

    func createCards(itemId: String, cardTypes: [String] = ["image_recall", "flashcard"]) async throws -> [AtlasCard] {
        let response: AtlasCardsResponse = try await APIClient.shared.post(
            .atlasItemCards(id: itemId),
            body: AtlasCardsPayload(cardTypes: cardTypes)
        )
        self.cards = Self.merged(self.cards, response.cards)
            .sorted { ($0.updatedAt ?? "") > ($1.updatedAt ?? "") }
        return response.cards
    }

    func deleteImage(id: String) async throws {
        try await APIClient.shared.delete(.atlasImage(id: id))
        self.images.removeAll { $0.id == id }
        self.items.removeAll { $0.imageId == id }
        self.cards.removeAll { $0.imageId == id }
    }

    /// Kick off (or re-run) AI enrichment for a custom item — fills
    /// definition / synonyms / forms / etymology so its detail page matches a
    /// dictionary word. itemId is the bare UUID (no "atlas:" prefix).
    func enrich(itemId: String) async throws {
        struct Ack: Decodable { let ok: Bool? }
        let _: Ack = try await APIClient.shared.post(.atlasItemEnrich(id: itemId), body: Empty())
    }

    /// Full per-word detail for a custom item (same `Word` shape as the
    /// dictionary), lazily enriched server-side on first fetch.
    func detail(itemId: String) async throws -> Word {
        try await APIClient.shared.get(.atlasItemDetail(id: itemId))
    }

    func loadStudyQueue(mode: String = "both", limit: Int = 20) async throws -> [AtlasStudyQueueItem] {
        let response: AtlasStudyQueueResponse = try await APIClient.shared.get(
            .atlasStudyQueue(mode: mode, limit: limit)
        )
        return response.queue
    }

    func answerStudyCard(
        cardId: String,
        rating: SRSRating,
        responseMs: Int?,
        sessionId: String,
        activity: String = "image_recall"
    ) async throws -> StudyAnswerResponse {
        try await APIClient.shared.post(
            .atlasStudyAnswer,
            body: AtlasStudyAnswerPayload(
                cardId: cardId,
                rating: rating,
                responseMs: responseMs,
                sessionId: sessionId,
                activity: activity
            )
        )
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
