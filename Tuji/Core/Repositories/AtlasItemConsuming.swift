import Foundation

/// Narrow role carved off `AtlasRepository` for the consumption actions on a
/// single public item — save / unsave / report — used by `AtlasPublicDetailVM`.
/// Reading (`publicItems`) is a separate seam, so a screen that only reads never
/// depends on a mutating method.
///
/// `LiveAtlasRepository` already implements it, so it conforms for free.
@MainActor
protocol AtlasItemConsuming {
    func save(slug: String) async throws -> AtlasSaveResponse
    func unsave(slug: String) async throws -> AtlasSaveResponse
    func report(slug: String, reason: AtlasReportReason, detail: String?) async throws
}

extension LiveAtlasRepository: AtlasItemConsuming {}
