// View model for AtlasPublicDetailView (a single public 圖鑑 item). Owns the
// consumption action state — save/unsave toggle, save count, in-flight guard,
// error line, report-sent flag — behind the AtlasItemConsuming seam, so the view
// stays presentation-only and the save/report transitions are unit-testable
// (e.g. a failed unsave must not flip the toggle).
//
// Analytics stays in the view (VMs don't reach AnalyticsService): toggleSave
// returns the resulting saved state so the view fires .atlasPublicSaved itself.
// A successful save/unsave also refreshes WordsStore through an injected closure,
// so the 圖鑑's 社群圖鑑 theme reflects the mutation before the action completes.

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
    private let refreshWords: @MainActor () async -> Void

    init(
        item: AtlasPublicItem,
        repo: AtlasItemConsuming = LiveAtlasRepository.shared,
        refreshWords: @escaping @MainActor () async -> Void = {}
    ) {
        self.item = item
        self.repo = repo
        self.refreshWords = refreshWords
    }

    /// Restores the account-specific save state whenever a detail screen is
    /// created, instead of assuming every newly-created screen is unsaved.
    func loadSaveState() async {
        guard !self.busy else { return }
        self.busy = true
        self.actionError = nil
        defer { self.busy = false }
        do {
            let response = try await self.repo.saveState(slug: self.item.slug)
            self.saved = response.saved
            self.saveCount = response.saveCount
        } catch is CancellationError {
            // Navigating away cancels the view task; no user-facing error needed.
        } catch {
            // This is a background refresh. If it fails, keep the safe default
            // and let an explicit save/unsave action surface any real error.
        }
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
            await self.refreshWords()
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
