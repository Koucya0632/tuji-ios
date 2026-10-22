import Foundation

/// Narrow public-shelf role used by `PublicAtlasBrowsingModel`. Saved/private
/// shelf reads remain on `CollectionBookmarking`, so each dependency still
/// exposes only its own policy boundary.
///
/// `LiveAtlasRepository` already implements it, so it conforms for free.
@MainActor
protocol CollectionsBrowsing {
    func publicCollections(lang: TargetLanguage, forceReload: Bool) async throws -> [AtlasCollection]
}

extension LiveAtlasRepository: CollectionsBrowsing {}

/// 物見 search. Its own seam so `AtlasSearchModel` can be driven by a stub.
@MainActor
protocol AtlasPublicSearching {
    func searchPublic(q: String, lang: TargetLanguage) async throws -> AtlasPublicSearchResponse
}

extension LiveAtlasRepository: AtlasPublicSearching {}
