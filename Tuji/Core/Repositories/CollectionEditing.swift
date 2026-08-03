import Foundation

/// Narrow role carved off `AtlasRepository` for the collection-edit screen — the
/// exact seven methods `CollectionEditVM` needs. A test fake stubs seven methods
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
}

extension LiveAtlasRepository: CollectionEditing {}
