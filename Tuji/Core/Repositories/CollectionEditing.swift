import Foundation

/// Narrow role carved off `AtlasRepository` for the collection-edit screen — the
/// exact eight methods `CollectionEditVM` needs. A test fake stubs seven methods
/// instead of the full 25-method repository, and each screen depends only on the
/// surface it actually calls (see CONTEXT.md → architecture / role seams).
///
/// `LiveAtlasRepository` already implements all seven, so it conforms for free.
@MainActor
protocol CollectionEditing {
    func collectionEdit(id: String) async throws -> AtlasCollectionEditResponse
    func updateCollection(
        id: String,
        title: String,
        description: String?,
        coverPublicItemId: String?
    ) async throws
    func updateCollectionAvatar(id: String, imageData: Data) async throws
        -> AtlasCollectionAvatarResponse
    func addCollectionItem(id: String, publicItemId: String) async throws
    func removeCollectionItem(id: String, publicItemId: String) async throws
    func publishCollection(id: String) async throws -> AtlasCollectionPublishResponse
    func withdrawCollection(id: String) async throws -> AtlasWithdrawResponse
    /// 刪除 lives on this screen because this is the 合集's own screen — the same
    /// place a 圖鑑卡片 is deleted from. It used to be a swipe on the list row,
    /// which was the only route there was and fought the list's own scrolling.
    func deleteCollection(id: String) async throws
}

extension LiveAtlasRepository: CollectionEditing {}
