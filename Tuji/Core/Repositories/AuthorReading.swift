import Foundation

/// Narrow role carved off `AtlasRepository` for the 作者主頁 screen (公開 browse) —
/// the one method `AuthorProfileVM` needs (see CONTEXT.md → architecture / role
/// seams). `LiveAtlasRepository` already implements it, so it conforms for free.
@MainActor
protocol AuthorReading {
    func author(username: String) async throws -> AtlasAuthorResponse
}

extension LiveAtlasRepository: AuthorReading {}
