import Foundation

/// Narrow role carved off `AtlasRepository` for the collection-edit screen — the
/// exact five methods `CollectionEditVM` needs. A test fake stubs five methods
/// instead of the full 25-method repository, and each screen depends only on the
/// surface it actually calls (see CONTEXT.md → architecture / role seams).
///
/// `LiveAtlasRepository` already implements all five, so it conforms for free.
@MainActor
protocol CollectionEditing {
    func collectionEdit(id: String) async throws -> AtlasCollectionEditResponse
    func updateCollection(
        id: String,
        title: String,
        description: String?,
        coverPublicItemId: String?
    ) async throws
    func addCollectionItem(id: String, publicItemId: String) async throws
    func removeCollectionItem(id: String, publicItemId: String) async throws
    func publishCollection(id: String) async throws -> AtlasCollectionPublishResponse
}

extension LiveAtlasRepository: CollectionEditing {}
