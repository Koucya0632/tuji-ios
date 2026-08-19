// What 首頁 says and offers, derived from the day's state.
//
// These eight decisions used to be `private var`s on `TodayView` — a 7-branch
// subtitle, a 5-branch block reason, a 3-level denominator fallback — reading
// across six environment stores inside a 802-line View. Nothing could reach
// them: no `@testable import` sees `private` instance state on a `View`, and no
// fake can be injected into one. The single piece that *was* tested is the one
// someone had already lifted out as a `static func` (`newQuotaAdjustment`), and
// its doc comment says exactly why: "split from the localized string so the
// logic stays unit-testable without a bundle/locale."
//
// So this module follows that lead for all of them. It returns *enums*, not
// `LocalizedStringKey`s — the View owns the words, this owns the verdict. That
// split is what keeps it testable without a bundle, and it is also why a
// String-keyed `LocalizedStringKey` can no longer leak Chinese into a ja/en UI
// from here: there is no string to leak.

import Foundation

/// Which line sits under the greeting. One case per thing 首頁 can truthfully
/// say, in the order the rules resolve.
enum TodaySubtitle: Equatable {
    case guestBrowsing
    case guestLearned(count: Int)
    case pickThemes
    /// Stats have not arrived. A neutral line beats a wrong verdict —
    /// 「都學過了」 flashing on a brand-new account while the first fetch is in
    /// flight is worse than saying nothing specific.
    case unknown
    case reviewDue(count: Int)
    case goalReached
    case newDoneToday(count: Int)
    case newAvailable
    case allLearnedInThemes
}

/// Why 學新字 is unavailable, so the hero can explain the dead-end instead of
/// leaving a silently greyed button.
enum TodayNewBlock: Equatable {
    case none
    case noThemes
    case noCards
    /// An early/small theme (e.g. 廚房 — seeded first, so its cards carry the
    /// lowest ids and get drawn first) empties before the rest.
    case allLearned
    case reviewBacklog
}

/// Which caption the hero shows under its CTAs, when it shows one.
///
/// Three sources compete and only one may speak. The ordering — and the rule
/// that nothing is said until stats have arrived — lived in a `private var` on
/// `TodayView` alongside a second, hand-written copy of the "wait for stats"
/// guard that `subtitle` already expresses as `.unknown`.
///
/// The *copy* stays in the View: this names which of the three is talking.
enum TodayHeroHint: Equatable {
    case newBlocked
    case quotaAdjusted
    case nothingToReview
}

struct TodayDecisions {
    /// Every fact the decisions depend on, read once by the View from its
    /// environment. Long on purpose: this is the honest input set, and it used
    /// to be six store reads scattered through a View body.
    struct Inputs {
        var isGuest: Bool
        /// `SettingsStore.hasLoaded` — an empty theme list means nothing until
        /// settings have actually arrived.
        var settingsLoaded: Bool
        var studyCategories: [String]
        var dailyGoal: Int
        var stats: StudyStats?
        /// Guests have no SRS state; their progress is the local learned set.
        var guestLearnedCount: Int
        /// `!ProgressStore.categoryProgress.isEmpty`.
        var progressLoaded: Bool
        var seenInSelection: Int
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

    /// 完成度, scoped to the selection. The rule lives on `CompletionReadout`
    /// so 我's card asks the same question the same way — it used to carry its
    /// own copy, with a whole-dictionary fallback and no guest branch.
    var completion: CompletionReadout {
        CompletionReadout(
            .init(
                isGuest: self.inputs.isGuest,
                settingsLoaded: self.inputs.settingsLoaded,
                studyCategories: self.inputs.studyCategories,
                guestLearnedCount: self.inputs.guestLearnedCount,
                seenInSelection: self.inputs.seenInSelection,
                totalInSelection: self.inputs.totalInSelection,
                dictionaryCount: self.inputs.dictionaryCount,
                dictionaryCountInSelection: self.inputs.dictionaryCountInSelection
            )
        )
    }

    var showThemePrompt: Bool {
        self.completion.showsThemePrompt
    }

    var dailyGoalReached: Bool {
        guard !self.inputs.isGuest else { return false }
        let goal = max(1, self.inputs.dailyGoal)
        return (self.inputs.stats?.todayNew ?? 0) >= goal
    }

    var reviewDisabled: Bool {
        self.inputs.isGuest || (self.inputs.stats?.due ?? 0) == 0
    }

    /// New words still to learn within the selected themes: (total − seen)
    /// scoped to the selection, derived from progress so it tracks the
    /// selection without a stats refetch. Falls back to the global `new` count
    /// before progress loads.
    var newAvailable: Int {
        guard self.inputs.progressLoaded else { return self.inputs.stats?.new ?? 0 }
        return max(0, self.inputs.totalInSelection - self.inputs.seenInSelection)
    }

    var newBlock: TodayNewBlock {
        // Guests can't study new words; the prompt to sign in lives elsewhere.
        if self.inputs.isGuest { return .none }
        // No themes selected → nothing to draw new words from (review stays
        // available — it spans all studied words).
        if self.inputs.studyCategories.isEmpty { return .noThemes }
        // total == 0 with progress loaded means the selected themes have no
        // cards in the current deck — e.g. a theme with no 日文 cards yet —
        // a different dead-end from "you've learned them all".
        if self.inputs.progressLoaded, self.inputs.totalInSelection == 0 { return .noCards }
        if self.newAvailable == 0 { return .allLearned }
        // When the review backlog crowds out the new-card quota
        // (computeNewLimit hits 0 once due > 100), grey the button out instead
        // of letting the user enter the launcher only to bounce back empty.
        if StudyQuotas.computeNewLimit(
            goal: max(1, self.inputs.dailyGoal),
            due: self.inputs.stats?.due ?? 0
        ) == 0 {
            return .reviewBacklog
        }
        return .none
    }

    var newDisabled: Bool {
        self.inputs.isGuest || self.newBlock != .none
    }

    var subtitle: TodaySubtitle {
        if self.inputs.isGuest {
            let learned = self.inputs.guestLearnedCount
            return learned > 0 ? .guestLearned(count: learned) : .guestBrowsing
        }
        if self.showThemePrompt { return .pickThemes }
        guard let stats = self.inputs.stats else { return .unknown }
        if stats.due > 0 { return .reviewDue(count: stats.due) }
        // Goal reached wins over everything below so this line can never
        // contradict the 達成 badge on the hero card.
        if self.dailyGoalReached { return .goalReached }
        if let done = stats.todayNew, done > 0 { return .newDoneToday(count: done) }
        if self.newAvailable > 0 { return .newAvailable }
        return .allLearnedInThemes
    }

    /// The backlog-tapers-new-quota decision + counts. Unchanged rule, moved
    /// here from `TodayView.newQuotaAdjustment` so every 首頁 decision has one
    /// home instead of one having been rescued and the rest left behind.
    /// Which of the three captions the hero shows, if any.
    ///
    /// 新字被擋 wins over 配額調整 wins over 沒有要複習的字, and none of them
    /// speaks before stats have landed — a hint about today's numbers, shown
    /// before today's numbers exist, is a guess.
    var heroHint: TodayHeroHint? {
        if self.newBlock != .none, self.newBlock != .noThemes { return .newBlocked }
        if self.quotaAdjustment != nil { return .quotaAdjusted }
        if self.reviewDisabled, self.inputs.stats != nil { return .nothingToReview }
        return nil
    }

    var quotaAdjustment: (due: Int, limit: Int)? {
        guard !self.inputs.isGuest, let stats = self.inputs.stats else { return nil }
        let goal = max(1, self.inputs.dailyGoal)
        guard (stats.todayNew ?? 0) < goal else { return nil }
        guard self.newAvailable > 0 else { return nil }
        let limit = StudyQuotas.computeNewLimit(goal: goal, due: stats.due)
        guard limit > 0, limit < goal else { return nil }
        return (due: stats.due, limit: limit)
    }
}
