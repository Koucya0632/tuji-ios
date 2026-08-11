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
