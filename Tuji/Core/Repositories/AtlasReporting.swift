import Foundation

/// Reporting the two public things that are not an item: the 合集 that curates
/// them and the author identity attached to both.
///
/// A separate role from `AtlasItemConsuming` because the consumer is different —
/// 合集詳情 and 作者主頁 never save or unsave, and the item detail never reports
/// a collection. Each screen depends only on the slice it uses (ADR-0001).
///
/// `LiveAtlasRepository` already implements it, so it conforms for free.
@MainActor
protocol AtlasReporting {
    func reportCollection(slug: String, reason: AtlasReportReason, detail: String?) async throws
    func reportAuthor(handle: String, reason: AtlasReportReason, detail: String?) async throws
}

extension LiveAtlasRepository: AtlasReporting {}
