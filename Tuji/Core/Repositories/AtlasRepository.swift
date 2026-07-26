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
    func publish(itemId: String) async throws -> AtlasPublishResponse
    func publicItems(lemma: String, language: TargetLanguage, limit: Int) async throws -> [AtlasPublicItem]
    func publicFeed(limit: Int) async throws -> [AtlasPublicItem]
    func author(username: String) async throws -> AtlasAuthorResponse
    func save(slug: String) async throws -> AtlasSaveResponse
    func unsave(slug: String) async throws -> AtlasSaveResponse
    func report(slug: String, reason: AtlasReportReason, detail: String?) async throws
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
        // Upload performs the first recognition inline, so it needs the same
        // live language context as an explicit recognize request. Do not rely
        // only on the debounced server settings after an in-app switch.
        let settings = SettingsStore.shared.current
        var fields: [String: String] = [
            "lang": settings.uiLang,
            "learning": settings.learningDirection.rawValue
        ]
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
        let settings = SettingsStore.shared.current
        return try await self.api.post(
            .atlasImageRecognize(
                id: imageId,
                lang: settings.uiLang,
                learning: settings.learningDirection.rawValue
            ),
            body: Payload(mode: mode.rawValue)
        )
    }

    func confirm(imageId: String, payload: AtlasConfirmPayload) async throws -> AtlasItem {
        let response: AtlasItemResponse = try await self.api.post(
            .atlasImageConfirm(id: imageId, lang: SettingsStore.shared.current.uiLang),
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

    /// Submits an item for public review. This is a *submission*, not a publish:
    /// the server runs a machine gate that may publish it, queue it for a human,
    /// or reject it — see `AtlasPublishResponse.moderation`.
    func publish(itemId: String) async throws -> AtlasPublishResponse {
        try await self.api.post(.atlasItemPublish(id: itemId), body: Empty())
    }

    /// Other users' public 圖鑑 for one word. Public endpoint — no bearer token,
    /// and it honors the server's CDN cache headers.
    func publicItems(
        lemma: String,
        language: TargetLanguage,
        limit: Int = 12
    ) async throws -> [AtlasPublicItem] {
        let response: AtlasPublicByLemmaResponse = try await self.api.get(
            .atlasPublicByLemma(lemma: lemma, lang: language.rawValue, limit: limit)
        )
        return response.items
    }

    func publicFeed(limit: Int = 60) async throws -> [AtlasPublicItem] {
        let response: AtlasPublicFeedResponse = try await self.api.get(.atlasPublicFeed(limit: limit))
        return response.items
    }

    func author(username: String) async throws -> AtlasAuthorResponse {
        try await self.api.get(.atlasPublicAuthor(username: username))
    }

    /// Saving is the CONSUMPTION path — it does not touch the user's 自製圖鑑
    /// capacity (docs/COMMUNITY_ATLAS_PLAN.md §4.1).
    func save(slug: String) async throws -> AtlasSaveResponse {
        try await self.api.post(.atlasPublicSave(slug: slug), body: Empty())
    }

    func unsave(slug: String) async throws -> AtlasSaveResponse {
        // The backend answers DELETE with the updated save state, so this uses
        // the decoding delete rather than APIClient.delete (which discards it).
        try await self.api.delete(.atlasPublicSave(slug: slug), as: AtlasSaveResponse.self)
    }

    func report(slug: String, reason: AtlasReportReason, detail: String?) async throws {
        struct Ack: Decodable { let ok: Bool? }
        let _: Ack = try await self.api.post(
            .atlasPublicReport(slug: slug),
            body: AtlasReportPayload(reason: reason.rawValue, detail: detail)
        )
    }
}
