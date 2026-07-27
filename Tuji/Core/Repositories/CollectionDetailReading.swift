import Foundation

/// Narrow role carved off `AtlasRepository` for the 合集 detail screen (公開 browse)
/// — the one method `CollectionDetailVM` needs (see CONTEXT.md → architecture /
/// role seams). `LiveAtlasRepository` already implements it, so it conforms free.
@MainActor
protocol CollectionDetailReading {
    func collection(slug: String) async throws -> AtlasCollectionDetailResponse
}

extension LiveAtlasRepository: CollectionDetailReading {}
