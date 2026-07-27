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
    func publicFeed(limit: Int, forceReload: Bool) async throws -> [AtlasPublicItem]
    func author(username: String) async throws -> AtlasAuthorResponse
    func save(slug: String) async throws -> AtlasSaveResponse
    func unsave(slug: String) async throws -> AtlasSaveResponse
    func report(slug: String, reason: AtlasReportReason, detail: String?) async throws

    // Community collections 合集
    func publicCollections(lang: TargetLanguage, forceReload: Bool) async throws -> [AtlasCollection]
    func collection(slug: String) async throws -> AtlasCollectionDetailResponse
    func myCollections() async throws -> [AtlasMyCollection]
    func createCollection(
        title: String, description: String?, targetLanguage: TargetLanguage
    ) async throws -> AtlasMyCollection
    func collectionEdit(id: String) async throws -> AtlasCollectionEditResponse
    func updateCollection(
        id: String, title: String, description: String?, coverPublicItemId: String?
    ) async throws
    func deleteCollection(id: String) async throws
    func addCollectionItem(id: String, publicItemId: String) async throws
    func removeCollectionItem(id: String, publicItemId: String) async throws
    func publishCollection(id: String) async throws -> AtlasCollectionPublishResponse
    func collectionCandidates(lang: TargetLanguage) async throws -> [AtlasPublicItem]
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

    /// `forceReload` bypasses the disk URLCache (pull-to-refresh, or right after
    /// publishing) so a freshly published item shows up immediately rather than
    /// waiting for the cached list to expire.
    func publicFeed(limit: Int = 60, forceReload: Bool = false) async throws -> [AtlasPublicItem] {
        let response: AtlasPublicFeedResponse = try await self.api.get(
            .atlasPublicFeed(limit: limit),
            cachePolicy: forceReload ? .reloadIgnoringLocalCacheData : nil
        )
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

    // MARK: - Community collections 合集

    /// Public browse feed, scoped to one learning language. `forceReload`
    /// bypasses the URLCache (pull-to-refresh / right after publishing).
    func publicCollections(
        lang: TargetLanguage,
        forceReload: Bool = false
    ) async throws -> [AtlasCollection] {
        // On force-reload, a nonce query param makes this a distinct edge-cache
        // key so Vercel serves a fresh list (the on-device cache bypass alone
        // can't beat the CDN copy).
        let cacheBust = forceReload ? String(Int(Date().timeIntervalSince1970)) : nil
        let response: AtlasPublicCollectionsResponse = try await self.api.get(
            .atlasPublicCollections(lang: lang.rawValue, limit: 60, cacheBust: cacheBust),
            cachePolicy: forceReload ? .reloadIgnoringLocalCacheData : nil
        )
        return response.collections
    }

    func collection(slug: String) async throws -> AtlasCollectionDetailResponse {
        try await self.api.get(.atlasPublicCollection(slug: slug))
    }

    func myCollections() async throws -> [AtlasMyCollection] {
        let response: AtlasMyCollectionsResponse = try await self.api.get(.atlasCollections)
        return response.collections
    }

    func createCollection(
        title: String,
        description: String?,
        targetLanguage: TargetLanguage
    ) async throws -> AtlasMyCollection {
        let response: AtlasMyCollectionResponse = try await self.api.post(
            .atlasCollections,
            body: AtlasCollectionCreatePayload(
                title: title,
                description: description,
                targetLanguage: targetLanguage.rawValue
            )
        )
        return response.collection
    }

    func collectionEdit(id: String) async throws -> AtlasCollectionEditResponse {
        try await self.api.get(.atlasCollection(id: id))
    }

    func updateCollection(
        id: String,
        title: String,
        description: String?,
        coverPublicItemId: String?
    ) async throws {
        let _: Empty = try await self.api.patch(
            .atlasCollection(id: id),
            body: AtlasCollectionUpdatePayload(
                title: title,
                description: description,
                coverPublicItemId: coverPublicItemId
            )
        )
    }

    func deleteCollection(id: String) async throws {
        try await self.api.delete(.atlasCollection(id: id))
    }

    func addCollectionItem(id: String, publicItemId: String) async throws {
        let _: Empty = try await self.api.post(
            .atlasCollectionItems(id: id),
            body: AtlasCollectionAddItemPayload(publicItemId: publicItemId)
        )
    }

    func removeCollectionItem(id: String, publicItemId: String) async throws {
        try await self.api.delete(.atlasCollectionItem(id: id, publicItemId: publicItemId))
    }

    func publishCollection(id: String) async throws -> AtlasCollectionPublishResponse {
        try await self.api.post(.atlasCollectionPublish(id: id), body: Empty())
    }

    /// The user's own approved public items in a language — the add-member pool.
    func collectionCandidates(lang: TargetLanguage) async throws -> [AtlasPublicItem] {
        let response: AtlasPublicFeedResponse = try await self.api.get(
            .atlasCollectionCandidates(lang: lang.rawValue)
        )
        return response.items
    }
}
