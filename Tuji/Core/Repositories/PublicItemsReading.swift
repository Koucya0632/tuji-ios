import Foundation

/// Narrow role carved off `AtlasRepository` for reading other users' public 圖鑑
/// items — the one method `WordCommunityAtlasSection` needs, so its substitute
/// stubs one method (see CONTEXT.md → architecture / role seams).
///
/// `LiveAtlasRepository` already implements it, so it conforms for free.
@MainActor
protocol PublicItemsReading {
    func publicItems(lemma: String, language: TargetLanguage, limit: Int) async throws -> [AtlasPublicItem]
}

extension LiveAtlasRepository: PublicItemsReading {}
