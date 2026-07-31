import Foundation

/// Authenticated batch learning action for an unlocked public collection.
@MainActor
protocol CollectionLearning {
    func learnCollection(slug: String) async throws -> AtlasCollectionLearnResponse
}

extension LiveAtlasRepository: CollectionLearning {}
