// View model for AtlasPublicDetailView (a single public 圖鑑 item). Owns the
// consumption action state — save/unsave toggle, save count, in-flight guard,
// error line, report-sent flag — behind the AtlasItemConsuming seam, so the view
// stays presentation-only and the save/report transitions are unit-testable
// (e.g. a failed unsave must not flip the toggle).
//
// Analytics stays in the view (VMs don't reach AnalyticsService): toggleSave
// returns the resulting saved state so the view fires .atlasPublicSaved itself.

import Foundation
import Observation

@MainActor
@Observable
final class AtlasPublicDetailVM {
    let item: AtlasPublicItem

    private(set) var saved = false
    private(set) var saveCount: Int?
    private(set) var busy = false
    private(set) var actionError: String?
    private(set) var reportSent = false

    private let repo: AtlasItemConsuming

    init(item: AtlasPublicItem, repo: AtlasItemConsuming = LiveAtlasRepository.shared) {
        self.item = item
        self.repo = repo
    }

    /// Save when unsaved, unsave when saved. Returns the resulting saved state on
    /// success (so the view can fire its save analytics), or nil when the call
    /// was skipped (already in flight) or failed — in which case the prior toggle
    /// state is preserved and `actionError` is set.
    @discardableResult
    func toggleSave() async -> Bool? {
        guard !self.busy else { return nil }
        self.busy = true
        self.actionError = nil
        let wasSaved = self.saved
        defer { self.busy = false }
        do {
            let response = wasSaved
                ? try await self.repo.unsave(slug: self.item.slug)
                : try await self.repo.save(slug: self.item.slug)
            self.saved = response.saved
            self.saveCount = response.saveCount
            return response.saved
        } catch {
            self.actionError = error.localizedDescription
            return nil
        }
    }

    func report(_ reason: AtlasReportReason) async {
        self.actionError = nil
        do {
            try await self.repo.report(slug: self.item.slug, reason: reason, detail: nil)
            self.reportSent = true
        } catch {
            self.actionError = error.localizedDescription
        }
    }
}
