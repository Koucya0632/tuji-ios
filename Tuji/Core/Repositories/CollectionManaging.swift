import Foundation

/// Narrow role carved off `AtlasRepository` for managing the signed-in user's
/// own 合集 — list the collections (`MyCollectionsVM`), create one
/// (`AtlasCollectionCreateSheet`), delete one from the management list, and
/// read the candidate-item pool (`AtlasCollectionItemPicker`).
///
/// `LiveAtlasRepository` already implements it, so it conforms for free.
@MainActor
protocol CollectionManaging {
    func myCollections() async throws -> [AtlasMyCollection]
    func createCollection(
        title: String,
        description: String?,
        targetLanguage: TargetLanguage
    ) async throws
        -> AtlasMyCollection
    func deleteCollection(id: String) async throws
    func collectionCandidates(lang: TargetLanguage) async throws -> [AtlasPublicItem]
}

extension LiveAtlasRepository: CollectionManaging {}
