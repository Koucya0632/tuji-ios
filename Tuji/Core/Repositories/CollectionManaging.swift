import Foundation

/// Narrow role carved off `AtlasRepository` for managing the signed-in user's
/// own 合集 — list the collections (`MyCollectionsVM`), create one
/// (`AtlasCollectionCreateSheet`), and read the candidate-item pool
/// (`AtlasCollectionItemPicker`). Each consumer uses one method of it.
///
/// (`deleteCollection` exists on the concrete repository but has no caller, so
/// it's intentionally not part of this seam — see ADR-0001's lazy-narrowing.)
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
    func collectionCandidates(lang: TargetLanguage) async throws -> [AtlasPublicItem]
}

extension LiveAtlasRepository: CollectionManaging {}
