import Foundation

/// Concrete atlas API client. Its surface reaches callers through focused role
/// protocols — `AtlasAuthoring`, `CollectionEditing`, `CollectionsBrowsing`,
/// `CollectionDetailReading`, `AuthorReading`, `PublicItemsReading`,
/// `AtlasItemConsuming`, `CollectionBookmarking`, `CollectionManaging` — each
/// conformed in its own file, so every consumer (and its test fake) depends only
/// on the slice it uses. No screen binds to this concrete type any more. The only
/// member behind no seam is `publicFeed`, which has no caller (per ADR-0001's
/// lazy-narrowing, a seam is carved when a consumer needs it).
@MainActor
struct LiveAtlasRepository {
    static let shared = LiveAtlasRepository()

    private let api: APIClient
    private let settings: LanguageContext

    init(api: APIClient = .shared, settings: LanguageContext = SettingsStore.shared) {
        self.api = api
        self.settings = settings
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
        var fields: [String: String] = [
            "lang": self.settings.uiLang,
            "learning": self.settings.learningDirection.rawValue
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
        return try await self.api.post(
            .atlasImageRecognize(
                id: imageId,
                lang: self.settings.uiLang,
                learning: self.settings.learningDirection.rawValue
            ),
            body: Payload(mode: mode.rawValue)
        )
    }

    func confirm(imageId: String, payload: AtlasConfirmPayload) async throws -> AtlasItem {
        let response: AtlasItemResponse = try await self.api.post(
            .atlasImageConfirm(id: imageId, lang: self.settings.uiLang),
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

    /// 取消公開 — pulls the item back off the community wall. Not a delete: the
    /// card, its study history and other people's saves all survive, and the
    /// item can be submitted again.
    func withdraw(itemId: String) async throws -> AtlasWithdrawResponse {
        try await self.api.post(.atlasItemWithdraw(id: itemId), body: Empty())
    }

    /// Other users' public 圖鑑 for one word. Public endpoint — no bearer token,
    /// and it honors the server's CDN cache headers.
    func publicItems(
        lemma: String,
        language: TargetLanguage,
        limit: Int = 12
    ) async throws
        -> [AtlasPublicItem]
    {
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

    /// One public item by slug. The 圖鑑 page's 社群圖鑑 cards carry only the
    /// word shape, so opening one fetches the parts the detail screen needs and
    /// the word payload deliberately doesn't carry: author, save count, slug.
    func publicItem(slug: String) async throws -> AtlasPublicItem {
        let response: AtlasPublicItemResponse = try await self.api.get(
            .atlasPublicItem(
                slug: slug,
                lang: SettingsStore.shared.current.uiLanguage.contentLanguageCode
            )
        )
        return response.item
    }

    func author(handle: String, forceReload: Bool = false) async throws -> AtlasAuthorResponse {
        // Same nonce trick as `publicCollections`: bypassing the on-device cache
        // alone can't beat the CDN copy, so a fresh read needs a distinct URL.
        let cacheBust = forceReload ? String(Int(Date().timeIntervalSince1970)) : nil
        return try await self.api.get(
            .atlasPublicAuthor(handle: handle, cacheBust: cacheBust),
            cachePolicy: forceReload ? .reloadIgnoringLocalCacheData : nil
        )
    }

    /// Saving is the CONSUMPTION path — it does not touch the user's 自製圖鑑
    /// capacity (docs/COMMUNITY_ATLAS_PLAN.md §4.1).
    func saveState(slug: String) async throws -> AtlasSaveResponse {
        try await self.api.get(
            .atlasPublicSave(slug: slug),
            cachePolicy: .reloadIgnoringLocalCacheData
        )
    }

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
    ) async throws
        -> [AtlasCollection]
    {
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

    func savedCollections(lang: TargetLanguage) async throws -> [AtlasCollection] {
        let response: AtlasPublicCollectionsResponse = try await self.api.get(
            .atlasSavedCollections(lang: lang.rawValue, limit: 100)
        )
        return response.collections
    }

    func collectionSaveState(slug: String) async throws -> AtlasSaveResponse {
        try await self.api.get(.atlasPublicCollectionSave(slug: slug))
    }

    func saveCollection(slug: String) async throws -> AtlasSaveResponse {
        try await self.api.post(.atlasPublicCollectionSave(slug: slug), body: Empty())
    }

    func unsaveCollection(slug: String) async throws -> AtlasSaveResponse {
        try await self.api.delete(
            .atlasPublicCollectionSave(slug: slug),
            as: AtlasSaveResponse.self
        )
    }

    func learnCollection(slug: String) async throws -> AtlasCollectionLearnResponse {
        try await self.api.post(
            .atlasPublicCollectionLearn(slug: slug),
            body: Empty()
        )
    }

    func myCollections() async throws -> [AtlasMyCollection] {
        let response: AtlasMyCollectionsResponse = try await self.api.get(.atlasCollections)
        return response.collections
    }

    func createCollection(
        title: String,
        description: String?,
        targetLanguage: TargetLanguage
    ) async throws
        -> AtlasMyCollection
    {
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

    /// 取消公開合集. Members stay published — the shelf comes down, not the
    /// photos on it, each of which is public in its own right.
    func withdrawCollection(id: String) async throws -> AtlasWithdrawResponse {
        try await self.api.post(.atlasCollectionWithdraw(id: id), body: Empty())
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
