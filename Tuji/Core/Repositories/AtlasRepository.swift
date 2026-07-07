import Foundation

@MainActor
protocol AtlasRepository {
    func sync(since: String?, limit: Int) async throws -> AtlasSyncResponse
    func uploadImage(
        data: Data,
        filename: String,
        mimeType: String,
        targetLanguage: TargetLanguage?
    ) async throws
        -> AtlasUploadResponse
    func recognize(imageId: String, mode: AtlasRecognitionMode) async throws -> AtlasRecognitionResponse
    func confirm(imageId: String, payload: AtlasConfirmPayload) async throws -> AtlasItem
    func createCards(itemId: String, cardTypes: [String]) async throws -> [AtlasCard]
    func deleteImage(id: String) async throws
    func enrich(itemId: String) async throws
    func detail(itemId: String) async throws -> Word
    func entitlement() async throws -> AtlasEntitlement
}

@MainActor
struct LiveAtlasRepository: AtlasRepository {
    static let shared = LiveAtlasRepository()

    private let api: APIClient

    init(api: APIClient = .shared) {
        self.api = api
    }

    func sync(since: String?, limit: Int) async throws -> AtlasSyncResponse {
        try await self.api.get(.atlasSync(since: since, limit: limit))
    }

    func uploadImage(
        data: Data,
        filename: String,
        mimeType: String,
        targetLanguage: TargetLanguage?
    ) async throws
        -> AtlasUploadResponse
    {
        var fields: [String: String] = [:]
        if let targetLanguage {
            fields["targetLanguage"] = targetLanguage.rawValue
        }
        return try await self.api.upload(
            .atlasImages(limit: 30),
            fileField: "file",
            filename: filename,
            mimeType: mimeType,
            data: data,
            fields: fields
        )
    }

    func recognize(imageId: String, mode: AtlasRecognitionMode) async throws -> AtlasRecognitionResponse {
        struct Payload: Encodable { let mode: String }
        return try await self.api.post(.atlasImageRecognize(id: imageId), body: Payload(mode: mode.rawValue))
    }

    func confirm(imageId: String, payload: AtlasConfirmPayload) async throws -> AtlasItem {
        let response: AtlasItemResponse = try await self.api.post(
            .atlasImageConfirm(id: imageId),
            body: payload
        )
        return response.item
    }

    func createCards(itemId: String, cardTypes: [String]) async throws -> [AtlasCard] {
        let response: AtlasCardsResponse = try await self.api.post(
            .atlasItemCards(id: itemId),
            body: AtlasCardsPayload(cardTypes: cardTypes)
        )
        return response.cards
    }

    func deleteImage(id: String) async throws {
        try await self.api.delete(.atlasImage(id: id))
    }

    func enrich(itemId: String) async throws {
        struct Ack: Decodable { let ok: Bool? }
        let _: Ack = try await self.api.post(.atlasItemEnrich(id: itemId), body: Empty())
    }

    func detail(itemId: String) async throws -> Word {
        try await self.api.get(.atlasItemDetail(id: itemId))
    }

    func entitlement() async throws -> AtlasEntitlement {
        try await self.api.get(.atlasEntitlement)
    }
}
