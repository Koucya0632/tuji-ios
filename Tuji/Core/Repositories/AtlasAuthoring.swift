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
    func createCards(itemId: String, cardTypes: [String]) async throws -> [AtlasCard]
    func deleteImage(id: String) async throws
    func detail(itemId: String) async throws -> Word
    func entitlement() async throws -> AtlasEntitlement
    func withdraw(itemId: String) async throws -> AtlasWithdrawResponse
}

extension LiveAtlasRepository: AtlasAuthoring {}
