import Foundation

/// Narrow role carved off `AtlasRepository` for the 公開圖鑑 browse feed — the one
/// method `PublicFeedVM` needs, so its test fake stubs one method (see CONTEXT.md
/// → architecture / role seams).
///
/// `LiveAtlasRepository` already implements it, so it conforms for free.
@MainActor
protocol CollectionsBrowsing {
    func publicCollections(lang: TargetLanguage, forceReload: Bool) async throws -> [AtlasCollection]
}

extension LiveAtlasRepository: CollectionsBrowsing {}
