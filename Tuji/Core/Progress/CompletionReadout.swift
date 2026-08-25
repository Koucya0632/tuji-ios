// 完成度 — how far through the selected themes the account is, as one value.
//
// The rule had two implementations. `TodayDecisions.dexSeen/dexTotal` carried
// the corrected one; `MeProgressSections.seenTotal/dictTotal` carried the
// version from before the fix, private on a `View` struct where no test could
// reach it. They disagreed in three cases a user can reach:
//
//   - a guest who has learned words: 首頁 counted them, 我 read the server's
//     (empty) rows and said 0%;
//   - themes that hold no published cards (自定義 + 物見): 我 fell back to the
//     *whole* dictionary and printed 「已學 0 / 共 480 字」 — a denominator
//     describing a selection nobody made, which is exactly the bug
//     `dexTotal`'s doc comment describes as fixed;
//   - no themes picked at all: 首頁 reads 0 / 0 to match its empty state, 我
//     quietly widened to every category.
//
// One module now answers it, and the eight tests that already pinned the
// 首頁 side cover 我 for free.

import Foundation

/// What the denominator is describing — the label above the number changes
/// with it (「所選主題完成度」 vs 「圖鑑完成度」).
enum CompletionScope: Equatable {
    /// The user's picked 學習主題.
    case selectedThemes
    /// No selection, so the whole dictionary stands in.
    case wholeDictionary
    /// Nothing to describe yet: signed in, settings loaded, no themes picked.
    /// Reads 0 / 0 rather than inventing a denominator.
    case pending
}

struct CompletionReadout: Equatable {
    /// Every fact the rule depends on. Assembled by the screen from its
    /// environment; nothing in here is fetched.
    struct Inputs: Equatable {
        var isGuest: Bool
        /// `SettingsStore.hasLoaded` — an empty theme list means nothing until
        /// settings have actually arrived.
        var settingsLoaded: Bool
        var studyCategories: [String]
        /// Guests have no SRS state; their progress is the local learned set.
        var guestLearnedCount: Int
        /// `ProgressStore.seenCount(filter:)` over the selection.
        var seenInSelection: Int
        /// `ProgressStore.totalCount(filter:)` over the selection.
        var totalInSelection: Int
        /// Whole local dictionary — the denominator when no themes are picked.
        var dictionaryCount: Int
        /// Local dictionary scoped to the selection.
        var dictionaryCountInSelection: Int
    }

    let inputs: Inputs

    init(_ inputs: Inputs) {
        self.inputs = inputs
    }

    /// Signed in, settings have arrived, and no themes are picked. The screens
    /// both branch on this — 首頁 to show its 選擇主題 prompt, 我 to avoid
    /// labelling an all-category number as a scoped one.
    var showsThemePrompt: Bool {
        !self.inputs.isGuest
            && self.inputs.settingsLoaded
            && self.inputs.studyCategories.isEmpty
    }

    var scope: CompletionScope {
        if self.showsThemePrompt { return .pending }
        return self.inputs.studyCategories.isEmpty ? .wholeDictionary : .selectedThemes
    }

    /// Words studied at least once (server "seen"). With no themes selected the
    /// progress reads 0 to match the "pick themes first" empty state.
    var seen: Int {
        if self.inputs.isGuest { return self.inputs.guestLearnedCount }
        if self.showsThemePrompt { return 0 }
        return self.inputs.seenInSelection
    }

    /// Total published words in the selected categories. Server count when
    /// available, else the locally known dictionary — scoped the same way.
    ///
    /// The fallback is scoped deliberately. Falling back to the *whole*
    /// dictionary fires not only when there is no server progress (guests,
    /// always) but also whenever the selected themes happen to hold nothing.
    var total: Int {
        if self.showsThemePrompt { return 0 }
        if self.inputs.totalInSelection > 0 { return self.inputs.totalInSelection }
        guard !self.inputs.studyCategories.isEmpty else { return self.inputs.dictionaryCount }
        return self.inputs.dictionaryCountInSelection
    }

    /// 0…1, clamped.
    var ratio: Double {
        Self.ratio(seen: self.seen, total: self.total)
    }

    /// The one seen/total ratio in the app, clamped and zero-safe.
    ///
    /// `seen` counts words the user has studied; `total` counts *published*
    /// cards. A withdrawn or taken-down word leaves seen > total, and the four
    /// hand-written copies of this expression disagreed about it — two clamped,
    /// two did not. `TujiProgressBar` clamps its own width, so the unclamped
    /// pair could print 「103%」 beside a bar pinned at full.
    static func ratio(seen: Int, total: Int) -> Double {
        guard total > 0 else { return 0 }
        return min(1, max(0, Double(seen) / Double(total)))
    }

    /// The whole-number percentage as rendered. Derived from `ratio`, so it
    /// cannot disagree with the bar beside it.
    var percent: Int {
        Int((self.ratio * 100).rounded())
    }
}

/// The 學習主題 selection, and whether it means anything yet.
///
/// A settings read seam in the shape `LanguageContext` already uses. Narrow
/// because it is the *scope* every number below is measured against: the bug
/// this module was built around is a denominator that stopped being scoped to
/// the selection, so "what is selected" and "has settings arrived" travel
/// together or not at all.
@MainActor
protocol StudySelectionReading {
    var studyCategories: [String] { get }
    /// An empty theme list means nothing until settings have actually arrived.
    var settingsLoaded: Bool { get }
}

extension SettingsStore: StudySelectionReading {
    var studyCategories: [String] {
        self.current.studyCategories
    }

    var settingsLoaded: Bool {
        self.hasLoaded
    }
}

/// A guest's progress, which is the local learned set rather than server rows.
///
/// A seam for one integer, because `LocalCache.init` is **private**: `.shared`
/// is the only instance that can exist, so a mapping that took the concrete type
/// could not be stood up in a test — the trap 圖鑑管理 already recorded ("a
/// `.shared`-defaulted seam whose init is private is not a seam"). The other
/// three stores this mapping reads all have an injectable `init(repository:)`
/// and stay concrete.
@MainActor
protocol GuestProgressReading {
    var learnedCount: Int { get }
}

extension LocalCache: GuestProgressReading {
    var learnedCount: Int {
        self.learnedIds.count
    }
}

extension CompletionReadout.Inputs {
    /// Read the eight facts out of the six stores that hold them.
    ///
    /// The *rule* had one home from the start; the *reading* had three — 首頁
    /// assembling `TodayDecisions.Inputs`, `TodayDecisions` copying eight of its
    /// eleven fields across field by field, and 我 assembling its own set from
    /// the same six stores. Two of the three lived in `View` bodies, so nothing
    /// could verify that the two screens were asking the same question, and
    /// once they were not: `isGuest` was answered two different ways and only
    /// agreed because `RootView` maps `.guest` to `user: nil` by hand.
    /// `ViewerIdentity` collapsed that one field. This collapses the other seven.
    ///
    /// **The stores are parameters, not properties.** Reading them inside the
    /// `View`'s body evaluation is what registers the `@Observable` dependency
    /// that re-renders 首頁 and 我 when any of them changes; a module that went
    /// and fetched them itself would read the same numbers and silently stop the
    /// screen from updating — an error with no compiler warning and no failing
    /// test. So the call stays in the body and only the mapping moves here.
    /// (`SettingsVM.clearProgress(learned:stores:)` takes its stores the same
    /// way, for the same reason.)
    @MainActor
    init(
        viewer: some ViewerIdentity,
        settings: some StudySelectionReading,
        progress: ProgressStore,
        words: WordsStore,
        cache: some GuestProgressReading
    ) {
        // Read once, then used as the filter for all four scoped numbers. It
        // being *the same* selection in all four places is the rule — 我 used to
        // fall back to the whole dictionary and print a denominator describing a
        // selection nobody made.
        let selected = settings.studyCategories
        self.init(
            isGuest: viewer.isGuest,
            settingsLoaded: settings.settingsLoaded,
            studyCategories: selected,
            guestLearnedCount: cache.learnedCount,
            seenInSelection: progress.seenCount(filter: selected),
            totalInSelection: progress.totalCount(filter: selected),
            dictionaryCount: words.words.count,
            dictionaryCountInSelection: words.count(inCategories: selected)
        )
    }
}
