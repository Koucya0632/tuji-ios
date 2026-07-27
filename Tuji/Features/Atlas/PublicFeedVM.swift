// View model for AtlasPublicFeedView (公開圖鑑 browse). Owns the language-scoped
// load state machine — including the "don't clobber a good list on back" guard
// that fixed the disappears-on-back bug — so the view stays presentation-only and
// the guard is a plain, unit-testable decision behind the CollectionsBrowsing seam.
//
// The view supplies the current learning language on each call (the feed follows
// SettingsStore, but the VM stays decoupled from it) and consumes the pending
// publish signal from AtlasFeedRefreshCenter itself, handing it in as a flag —
// keeping the VM free of the global.

import Foundation
import Observation

@MainActor
@Observable
final class PublicFeedVM {
    enum Phase: Equatable {
        case loading, ready, failed(String)
    }

    private(set) var collections: [AtlasCollection] = []
    private(set) var phase: Phase = .loading
    /// Language whose list is currently loaded, so returning from a detail doesn't
    /// refetch-and-clobber a good list.
    private(set) var loadedLang: TargetLanguage?

    private let repo: CollectionsBrowsing

    init(repo: CollectionsBrowsing = LiveAtlasRepository.shared) {
        self.repo = repo
    }

    /// Error line for the empty state; nil unless the last load failed.
    var errorMessage: String? {
        if case let .failed(message) = self.phase { return message }
        return nil
    }

    /// A plain appearance load re-triggers on every return from a detail. Skip it
    /// when we already hold this language's non-empty list and it isn't a
    /// deliberate refresh — a refetch can hit a stale edge/device copy and clobber
    /// the list with an empty one (the "disappears on back" bug).
    func shouldSkipLoad(lang: TargetLanguage, force: Bool) -> Bool {
        !force && self.loadedLang == lang && !self.collections.isEmpty
    }

    /// `forceReload` (pull-to-refresh / retry) and `pendingForce` (a publish that
    /// went live, consumed from AtlasFeedRefreshCenter by the view) both bypass the
    /// URLCache. Only a first/appearance load shows the full-screen spinner; a
    /// forced reload keeps the current list on screen.
    func load(lang: TargetLanguage, forceReload: Bool = false, pendingForce: Bool = false) async {
        let force = forceReload || pendingForce
        if self.shouldSkipLoad(lang: lang, force: force) { return }
        if !forceReload { self.phase = .loading }
        do {
            self.collections = try await self.repo.publicCollections(lang: lang, forceReload: force)
            self.loadedLang = lang
            self.phase = .ready
        } catch {
            // A failed forced reload keeps the list already on screen; only a fresh
            // (spinner) load clears it and surfaces the empty/error state.
            if !forceReload { self.collections = [] }
            self.phase = .failed(error.localizedDescription)
        }
    }
}
