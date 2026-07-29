import Foundation

/// Narrow role carved off `AtlasRepository` for the 作者主頁 screen (公開 browse) —
/// the one method `AuthorProfileVM` needs (see CONTEXT.md → architecture / role
/// seams). `LiveAtlasRepository` already implements it, so it conforms for free.
@MainActor
protocol AuthorReading {
    /// `forceReload` bypasses both caches — the on-device `URLCache` and, via a
    /// nonce query param, Vercel's 30-minute edge copy. The self-view always
    /// sets it, so an author who just edited their public identity sees the
    /// change rather than the version the CDN is still handing out.
    func author(handle: String, forceReload: Bool) async throws -> AtlasAuthorResponse
}

extension LiveAtlasRepository: AuthorReading {}
