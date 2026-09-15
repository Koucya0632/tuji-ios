// What the learning numbers on screen need re-read, for the causes no other
// refresh module owns.
//
// `SessionRefresh` (a finished session), `LearningDirectionRefresh` (a 學習語言
// switch) and `AtlasMutationRefresh` (a 圖鑑管理 mutation) each name their
// consequences. Four causes were left to their call sites, and two had drifted:
//
//   首頁 下拉          progress ✓ stats ✓ mastery ✓ words ✓ categories ✓ queue ✗
//   我 下拉            progress ✓ mastery ✗   ← 我 · 進度 draws the 熟練度 bar
//   清除學習進度        progress ✓ stats ✓ mastery ✗ queue ✗
//                      ← the prompt says 「將刪除掌握度」, and mastery has no TTL,
//                        so the cleared scores stayed until relaunch
//   換介面語言          words ✓ categories ✓ — reached as `.shared` inside
//                      SettingsStore, where no test could see it
//
// The account changing is not here: `AccountScopedStores` drops everything.

import Foundation

/// Something that makes learning numbers on screen stale.
enum LearningRefreshCause: Equatable {
    /// 首頁 pulled to refresh.
    case pulledToday(isGuest: Bool)
    /// 我 pulled to refresh.
    case pulledMe(isGuest: Bool)
    /// 設定 → 清除學習進度 succeeded on the server.
    case progressCleared
    /// 設定 → 語言 changed the interface language.
    case uiLanguageChanged
}

/// A store a refresh reaches, named by role, and how it is refreshed.
enum RefreshTarget: CaseIterable, Hashable {
    /// Invalidated, then re-read: the old copy is wrong, not merely old.
    case progress, stats, mastery
    /// Dropped. The next 複習 / 學新字 fetches a queue of its own.
    case queue
    /// Re-read in place. The dataset is the same one in other words, so the
    /// old text stays on screen until the new payload lands — no empty flash.
    case dictionary, themes
}

extension LearningRefreshCause {
    /// The whole policy. Guests have no account-scoped stores to refresh.
    var targets: Set<RefreshTarget> {
        switch self {
        case let .pulledToday(isGuest):
            isGuest ? [.dictionary, .themes] : [.progress, .stats, .mastery, .queue, .dictionary, .themes]
        case let .pulledMe(isGuest):
            // No stats: nothing on 我 reads due / new. Mastery: the 熟練度 bar.
            isGuest ? [] : [.progress, .mastery]
        case .progressCleared:
            // Everything the wipe emptied. The queue too: it was built from the
            // SRS schedule that no longer exists.
            [.progress, .stats, .mastery, .queue]
        case .uiLanguageChanged:
            [.dictionary, .themes]
        }
    }
}

@MainActor
protocol LearningRefreshing {
    func refresh(after cause: LearningRefreshCause) async
}

/// Reaches the singletons at call time, like `LiveLearningDirectionRefresher`:
/// `SettingsStore.shared` builds one of these in its own default argument.
@MainActor
struct LiveLearningRefresher: LearningRefreshing {
    private let learningStore: @MainActor (RefreshTarget) -> RefreshableStore?
    private let invalidateQueue: @MainActor () -> Void
    private let reloadDictionary: @MainActor () async -> Void
    private let reloadThemes: @MainActor () async -> Void

    init(
        learningStore: @escaping @MainActor (RefreshTarget) -> RefreshableStore? = { target in
            switch target {
            case .progress: ProgressStore.shared
            case .stats: StudyStatsStore.shared
            case .mastery: MasteryStore.shared
            case .queue, .dictionary, .themes: nil
            }
        },
        invalidateQueue: @escaping @MainActor () -> Void = { StudyQueueStore.shared.invalidate() },
        reloadDictionary: @escaping @MainActor () async -> Void = { await WordsStore.shared.reload() },
        reloadThemes: @escaping @MainActor () async -> Void = { await CategoriesStore.shared.reload() }
    ) {
        self.learningStore = learningStore
        self.invalidateQueue = invalidateQueue
        self.reloadDictionary = reloadDictionary
        self.reloadThemes = reloadThemes
    }

    /// Invalidate everything first, then re-read concurrently. The order is the
    /// rule: re-reading a store that still holds its pre-wipe copy refills it
    /// with what was there.
    func refresh(after cause: LearningRefreshCause) async {
        let targets = cause.targets
        let stores = RefreshTarget.allCases
            .filter { targets.contains($0) }
            .compactMap(self.learningStore)
        for store in stores {
            store.invalidate()
        }
        if targets.contains(.queue) {
            self.invalidateQueue()
        }
        var reloads = stores.map { store in Task { await store.reload() } }
        if targets.contains(.dictionary) {
            reloads.append(Task { await self.reloadDictionary() })
        }
        if targets.contains(.themes) {
            reloads.append(Task { await self.reloadThemes() })
        }
        for reload in reloads {
            await reload.value
        }
    }
}
