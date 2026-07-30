import Foundation

/// Private, authenticated collection-bookmark operations. Kept separate from
/// item consumption because a collection bookmark creates no learning cards.
@MainActor
protocol CollectionBookmarking {
    func savedCollections(lang: TargetLanguage) async throws -> [AtlasCollection]
    func collectionSaveState(slug: String) async throws -> AtlasSaveResponse
    func saveCollection(slug: String) async throws -> AtlasSaveResponse
    func unsaveCollection(slug: String) async throws -> AtlasSaveResponse
}

extension LiveAtlasRepository: CollectionBookmarking {}
