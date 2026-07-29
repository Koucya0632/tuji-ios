import Foundation

/// The 自製圖鑑 authoring + sync surface — the exact methods `AtlasStore` drives
/// (upload → 識別 → confirm → cards, plus sync / entitlement / publish). Carving it
/// off lets `AtlasStore` depend on this focused role instead of the whole atlas API,
/// and a future `AtlasStore` fake stubs ten methods rather than the full surface
/// (see CONTEXT.md → architecture / role seams).
///
/// `LiveAtlasRepository` already implements all of these, so it conforms for free.
@MainActor
protocol AtlasAuthoring {
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
    func withdraw(itemId: String) async throws -> AtlasWithdrawResponse
}

extension LiveAtlasRepository: AtlasAuthoring {}
