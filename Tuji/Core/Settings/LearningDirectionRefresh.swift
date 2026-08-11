// One policy home for "what a learning-direction switch reloads, and when".
//
// The rule was written by hand at four write sites and no two agreed:
//
//   SettingsView.select        words ✓ categories ✓ progress ✓ mastery ✓ stats ✓
//   OnboardingFlow.option      words ✓ categories ✓ progress ✗ mastery ✗ stats ✗
//   SettingsStore.performLoad  words ◐ categories ✗ progress ✓ mastery ✓ stats ✓
//   SetupView → adoptPersisted  — nothing —
//
// So picking 日文 from the first-run picker left yesterday's 英文 mastery,
// progress and streak on the home screen until something else happened to
// invalidate them. Two of the four lived in a SwiftUI `View` body, where no test
// could reach them, which is why the divergence went unnoticed: the picker view
// held seven `@Environment` stores to render two rows.
//
// Producers no longer name stores. `SettingsStore` is the only place the
// direction can change, so it detects the change and states the origin; this
// module owns the consequences. Mirrors AtlasMutationRefresh (authoring),
// CommunityLearningRefresh (consumption) and SessionRefresh (study).

import Foundation

/// How the app came to change 學習語言. The origin exists because one consequence
/// genuinely differs — not so producers can tune the fan-out.
enum LearningDirectionChangeOrigin: Equatable {
    /// The user picked it: 設定 → 學習語言, or the first-run picker. Everything the
    /// old direction filled is now wrong on screen and must be re-fetched here.
    case userPicked
    /// A server settings load disagreed with the direction in hand — a switch
    /// made on another device, or the first load after sign-in.
    case serverDisagreed

    /// Whether this module also re-fetches the catalog, or only drops it.
    ///
    /// `serverDisagreed` runs inside launch, where `LaunchCoordinator` owns the
    /// final context-aware words/categories load; re-fetching here would race it
    /// and extend the splash gate. Invalidation still happens in both cases —
    /// the stale catalog must never be served, whoever reloads it.
    var reloadsCatalog: Bool {
        switch self {
        case .userPicked: true
        case .serverDisagreed: false
        }
    }
}

@MainActor
protocol LearningDirectionRefreshing {
    func refresh(after origin: LearningDirectionChangeOrigin) async
}

/// Stateless live adapter. It deliberately has no lifecycle of its own; only
/// this module knows which app stores implement the policy.
@MainActor
struct LiveLearningDirectionRefresher: LearningDirectionRefreshing {
    private let invalidateCatalog: @MainActor () -> Void
    private let reloadCatalog: @MainActor () async -> Void
    private let invalidateQueue: @MainActor () -> Void
    private let learningStores: @MainActor () -> [RefreshableStore]

    /// Everything is a closure so the singletons are reached at call time rather
    /// than at construction — `SettingsStore.shared` builds one of these in its
    /// own default argument, and touching the stores there would be a cycle.
    init(
        invalidateCatalog: @escaping @MainActor () -> Void = {
            WordsStore.shared.invalidate()
            CategoriesStore.shared.invalidate()
        },
        reloadCatalog: @escaping @MainActor () async -> Void = {
            async let words: Void = WordsStore.shared.reload()
            async let categories: Void = CategoriesStore.shared.reload()
            _ = await (words, categories)
        },
        invalidateQueue: @escaping @MainActor () -> Void = {
            StudyQueueStore.shared.invalidate()
        },
        learningStores: @escaping @MainActor () -> [RefreshableStore] = {
            [MasteryStore.shared, ProgressStore.shared, StudyStatsStore.shared]
        }
    ) {
        self.invalidateCatalog = invalidateCatalog
        self.reloadCatalog = reloadCatalog
        self.invalidateQueue = invalidateQueue
        self.learningStores = learningStores
    }

    func refresh(after origin: LearningDirectionChangeOrigin) async {
        self.invalidateCatalog()
        // The prefetched queue survived every one of the four old fan-outs. It
        // only ever escaped serving the wrong direction's words because its own
        // cache signature carries the direction — a second guard for the same
        // fact, and the one nobody would think to add to a fifth producer.
        self.invalidateQueue()
        let stores = self.learningStores()
        for store in stores {
            store.invalidate()
        }
        // Concurrent: independent round-trips, and each Task inherits the main
        // actor, so they overlap on their network awaits without leaving it.
        var reloads = stores.map { store in Task { await store.reload() } }
        if origin.reloadsCatalog {
            reloads.append(Task { await self.reloadCatalog() })
        }
        for reload in reloads {
            await reload.value
        }
    }
}
