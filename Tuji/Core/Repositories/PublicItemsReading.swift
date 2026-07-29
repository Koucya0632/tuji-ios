import Foundation

/// Narrow role carved off `AtlasRepository` for reading other users' public 圖鑑
/// items — by lemma for `WordCommunityAtlasSection`, by slug for the 圖鑑 page's
/// 社群圖鑑 cards (see CONTEXT.md → architecture / role seams).
///
/// `LiveAtlasRepository` already implements it, so it conforms for free.
@MainActor
protocol PublicItemsReading {
    func publicItems(lemma: String, language: TargetLanguage, limit: Int) async throws -> [AtlasPublicItem]
    func publicItem(slug: String) async throws -> AtlasPublicItem
}

extension LiveAtlasRepository: PublicItemsReading {}
