import Foundation

/// What a 檢舉 is about. One type for the three things a user can report, so
/// screens name the target instead of picking an endpoint.
///
/// The three server calls differ only in which id they carry, which is why
/// three near-identical repository methods existed and why each caller had to
/// know which one to reach for.
enum ReportTarget: Equatable, Hashable {
    /// A public 物見 item, addressed by its slug.
    case item(slug: String)
    case collection(slug: String)
    /// An author identity, addressed by the immutable TJ UID.
    case author(handle: String)
}

/// One seam for submitting a 檢舉, whatever the target.
///
/// Replaces reaching for `AtlasItemConsuming.report`, `AtlasReporting
/// .reportCollection` or `.reportAuthor` at the call site. Two adapters justify
/// it: the live repository and the test fake — and the fake is the point, since
/// two of the three screens previously held
/// `private let reporter = LiveAtlasRepository.shared`, which no test could
/// substitute even from inside the module.
@MainActor
protocol ReportSubmitting {
    func submit(_ target: ReportTarget, reason: AtlasReportReason, detail: String?) async throws
}

extension LiveAtlasRepository: ReportSubmitting {
    func submit(
        _ target: ReportTarget,
        reason: AtlasReportReason,
        detail: String?
    ) async throws {
        switch target {
        case let .item(slug):
            try await self.report(slug: slug, reason: reason, detail: detail)
        case let .collection(slug):
            try await self.reportCollection(slug: slug, reason: reason, detail: detail)
        case let .author(handle):
            try await self.reportAuthor(handle: handle, reason: reason, detail: detail)
        }
    }
}
