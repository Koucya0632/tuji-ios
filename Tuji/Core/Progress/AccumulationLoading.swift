// What a screen that *reads* the accumulation numbers needs warm before those
// numbers are true.
//
// The app already had three modules naming what a *write* invalidates —
// `SessionRefresh` (a finished study session), `LearningDirectionRefresh` (a
// 學習語言 switch), `AtlasMutationRefresh` (a 圖鑑管理 mutation). Nothing named
// the reader's side, so each screen hand-wrote its own fan-out in `.task` and
// the three disagreed. `CategoryIndexView` was the one that got it wrong: it
// renders `ThemeStatus.of(… progress: progress.categoryProgress …)` but never
// loaded `ProgressStore`, so on a cold open of 主題 the 完成 badge was missing
// from every theme and appeared only if some other screen had warmed the store
// first. 全精通 kept working, because mastery *was* loaded — which is why the
// badge looked intermittent rather than broken.
//
// The policy (`needs`) is a pure function over the surface and the guest flag.
// The warming itself is glue.

import Foundation
import SwiftUI

/// A store the accumulation readout depends on. Named by role, not by type, so
/// the policy below can be read without knowing which concrete store is which.
enum AccumulationStore: CaseIterable {
    /// `WordsStore` — the local dictionary.
    case dictionary
    /// `CategoriesStore` — theme names and order.
    case themes
    /// `SettingsStore` — the 學習主題 selection and the 今日目標.
    case settings
    /// `ProgressStore` — streak, heatmap, per-theme seen/total.
    case progress
    /// `StudyStatsStore` — due / new / todayNew.
    case stats
    /// `MasteryStore` — per-word scores behind the 全精通 badge.
    case mastery
}

/// A screen that reads the accumulation numbers.
enum AccumulationSurface {
    /// 首頁 — the hero's 今日目標 + 主題進度, the streak chip, the theme strip.
    case todayHero
    /// 我 · 進度 — the 完成度 card, streak columns, heatmap, 明細.
    case progressSections
    /// 主題 — the theme index grid and its 完成 / 全精通 badges.
    case themeIndex

    /// Which stores must be warm for this surface's numbers to be true.
    ///
    /// Guests have no account-scoped data, so the three server-backed stores
    /// are dropped for them rather than fetched and 401'd. Their numbers come
    /// from `LocalCache` instead, which no screen has to load.
    func needs(isGuest: Bool) -> Set<AccumulationStore> {
        var stores: Set<AccumulationStore> = [.dictionary, .themes, .settings]
        if isGuest { return stores }
        switch self {
        case .todayHero:
            // The hero reads every one of them: 今日目標 needs stats.todayNew,
            // 主題進度 needs progress, the theme tiles need mastery.
            stores.formUnion([.progress, .stats, .mastery])
        case .progressSections:
            // No stats: nothing on 我 reads due / new. Mastery likewise — the
            // 明細 rows are seen/total, not scores.
            stores.insert(.progress)
        case .themeIndex:
            // Both badges: 全精通 from mastery, 完成 from progress. The second
            // one is the fix — this surface used to omit it.
            stores.formUnion([.progress, .mastery])
        }
        return stores
    }
}

/// One store, warmed. `loadIfNeeded()` / `loadIfStale()` differ by name and by
/// staleness policy; this is the shape they share.
@MainActor
protocol WarmableStore {
    func warm() async
}

extension WordsStore: WarmableStore {
    func warm() async {
        await self.loadIfNeeded()
    }
}

extension CategoriesStore: WarmableStore {
    func warm() async {
        await self.loadIfNeeded()
    }
}

extension SettingsStore: WarmableStore {
    func warm() async {
        await self.loadIfNeeded()
    }
}

extension ProgressStore: WarmableStore {
    func warm() async {
        await self.loadIfStale()
    }
}

extension StudyStatsStore: WarmableStore {
    func warm() async {
        await self.loadIfStale()
    }
}

extension MasteryStore: WarmableStore {
    func warm() async {
        await self.loadIfNeeded()
    }
}

@MainActor
struct AccumulationWarmer {
    let stores: [AccumulationStore: any WarmableStore]

    /// Warm everything `surface` needs.
    ///
    /// Settings goes first and alone: it is the only one of the six with
    /// consequences for the others. `SettingsStore` is where a server/device
    /// disagreement about 學習語言 is noticed, and noticing it invalidates and
    /// re-reads the learning stores (`LearningDirectionRefresh`) — so warming
    /// progress concurrently with settings would race a load against its own
    /// invalidation.
    ///
    /// The rest are awaited in sequence rather than in a task group on purpose.
    /// `any WarmableStore` is a non-Sendable existential, and sending one into
    /// a child task is rejected by the Swift 6 whole-module build while passing
    /// the Debug build — the same trap documented on `MeVM.load`. Every store
    /// here is guarded (a TTL or a once-flag), so on all but the first
    /// appearance the whole sequence is a no-op.
    func warm(_ surface: AccumulationSurface, isGuest: Bool) async {
        let needed = surface.needs(isGuest: isGuest)
        if needed.contains(.settings), let settings = self.stores[.settings] {
            await settings.warm()
        }
        for key in AccumulationStore.allCases where key != .settings {
            guard needed.contains(key), let store = self.stores[key] else { continue }
            await store.warm()
        }
    }
}

// MARK: - The screen-side seam

extension View {
    /// Warm what this surface's numbers depend on, then run `follow`.
    ///
    /// `follow` exists for 首頁, whose study-queue prefetch has to happen after
    /// settings and stats are warm — it reads both to build its params.
    func warmsAccumulation(
        _ surface: AccumulationSurface,
        isGuest: Bool,
        then follow: @escaping @MainActor () -> Void = {}
    )
        -> some View
    {
        self.modifier(
            AccumulationWarmModifier(surface: surface, isGuest: isGuest, follow: follow)
        )
    }
}

private struct AccumulationWarmModifier: ViewModifier {
    let surface: AccumulationSurface
    let isGuest: Bool
    let follow: @MainActor () -> Void

    @Environment(WordsStore.self) private var words
    @Environment(CategoriesStore.self) private var categories
    @Environment(SettingsStore.self) private var settings
    @Environment(ProgressStore.self) private var progress
    @Environment(StudyStatsStore.self) private var stats
    @Environment(MasteryStore.self) private var mastery

    func body(content: Content) -> some View {
        content.task {
            await AccumulationWarmer(
                stores: [
                    .dictionary: self.words,
                    .themes: self.categories,
                    .settings: self.settings,
                    .progress: self.progress,
                    .stats: self.stats,
                    .mastery: self.mastery
                ]
            )
            .warm(self.surface, isGuest: self.isGuest)
            self.follow()
        }
    }
}
