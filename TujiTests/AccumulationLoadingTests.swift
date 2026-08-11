// Pins the reader-side warm policy — what each accumulation surface needs
// loaded before its numbers are true.
//
// The first test is the bug this module exists for: 主題 renders the 完成 badge
// from ProgressStore and never loaded it, so the badge appeared only when some
// other screen had warmed the store first.

import Testing
@testable import Tuji

struct AccumulationSurfaceNeedsTests {
    @Test("主題 needs progress — 完成 is drawn from it")
    func themeIndexNeedsProgress() {
        let needs = AccumulationSurface.themeIndex.needs(isGuest: false)
        #expect(needs.contains(.progress))
        // 全精通 comes from mastery; that half always worked.
        #expect(needs.contains(.mastery))
    }

    @Test("首頁's hero reads every store")
    func todayHeroNeedsAll() {
        let needs = AccumulationSurface.todayHero.needs(isGuest: false)
        #expect(needs == Set(AccumulationStore.allCases))
    }

    @Test("我 · 進度 asks for nothing it does not render")
    func progressSectionsSkipsStatsAndMastery() {
        let needs = AccumulationSurface.progressSections.needs(isGuest: false)
        #expect(needs.contains(.progress))
        // Nothing on the 進度 sections reads due/new, or a per-word score.
        #expect(!needs.contains(.stats))
        #expect(!needs.contains(.mastery))
    }

    @Test("a guest never reaches for account-scoped data")
    func guestsSkipTheServerStores() {
        let surfaces: [AccumulationSurface] = [.todayHero, .progressSections, .themeIndex]
        for surface in surfaces {
            let needs = surface.needs(isGuest: true)
            #expect(needs == [.dictionary, .themes, .settings])
        }
    }
}

@MainActor
struct AccumulationWarmerTests {
    @Test("only what the surface needs is warmed")
    func warmsExactlyTheNeededStores() async {
        var warmed: [AccumulationStore] = []
        let warmer = AccumulationWarmer(stores: Self.spies { warmed.append($0) })

        await warmer.warm(.progressSections, isGuest: false)

        #expect(Set(warmed) == [.dictionary, .themes, .settings, .progress])
    }

    @Test("settings is warmed before anything that a direction switch would drop")
    func settingsGoesFirst() async {
        // SettingsStore is where a server/device disagreement about 學習語言 is
        // noticed, and noticing it invalidates the learning stores. Warming
        // progress alongside it would race a load against its own invalidation.
        var warmed: [AccumulationStore] = []
        let warmer = AccumulationWarmer(stores: Self.spies { warmed.append($0) })

        await warmer.warm(.todayHero, isGuest: false)

        #expect(warmed.first == .settings)
        #expect(Set(warmed) == Set(AccumulationStore.allCases))
    }

    @Test("a guest's warm touches no account-scoped store")
    func guestWarmStaysLocal() async {
        var warmed: [AccumulationStore] = []
        let warmer = AccumulationWarmer(stores: Self.spies { warmed.append($0) })

        await warmer.warm(.todayHero, isGuest: true)

        #expect(Set(warmed) == [.dictionary, .themes, .settings])
    }

    private static func spies(
        _ record: @escaping (AccumulationStore) -> Void
    )
        -> [AccumulationStore: any WarmableStore]
    {
        var stores: [AccumulationStore: any WarmableStore] = [:]
        for key in AccumulationStore.allCases {
            stores[key] = SpyWarmable(key: key, record: record)
        }
        return stores
    }
}

@MainActor
private final class SpyWarmable: WarmableStore {
    let key: AccumulationStore
    let record: (AccumulationStore) -> Void

    init(key: AccumulationStore, record: @escaping (AccumulationStore) -> Void) {
        self.key = key
        self.record = record
    }

    func warm() async {
        self.record(self.key)
    }
}
