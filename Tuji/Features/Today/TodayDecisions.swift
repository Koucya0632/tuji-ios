// What 首頁 says and offers, derived from the day's state.
//
// 墨塊從「兩條進度 + 兩顆按鈕 + 一行提示」收成「一個標題 + 一條總進度 +
// 一顆按鈕 + 最多一行」之後，這裡答的問題也跟著換了：`subtitle` 的七個
// case 跟 `heroHint` 的三個，收斂成 `heading` / `call` / `footer`。
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

/// 墨塊的標題說什麼。View 拿 id 去查名字 —— 這個模組不認得主題的名字，
/// 也不該認得：它答的是「有沒有主題、第一個是哪個、總共幾個」。
enum TodayHeading: Equatable {
    /// Settings 還沒到。沒有名字可以報，也還不能說「沒選主題」—— 一個空的
    /// 主題清單在 settings 落地之前什麼都不代表。
    case unknown
    case noThemes
    case themes(firstId: String, count: Int)
}

/// 背單字 這顆按鈕待會會做什麼。
///
/// 它取代了原本並排的 複習／學新字。模式不再是使用者選的，是這裡挑的 ——
/// 有欠複習就複習，否則學新字。規則本身不是新的（打卡表單的 `studyFromCheckIn`
/// 早就是這樣選），新的是它成了唯一的入口：一個有字要複習的人，不能再自己
/// 決定今天只學新字。`footer` 的 `.switchToNew` 是那條退路。
enum TodayCall: Equatable {
    /// 還沒選主題 —— 按鈕直接去選。
    case pickThemes
    /// stats 還沒到。按鈕照樣可以按，只是說不出數字 ——
    /// 一個在第一次抓取落地前就報出來的數量是猜的。
    case unknown
    case study(mode: StudyMode, count: Int)
    case blocked(TodayBlock)
}

/// 按鈕死掉的兩個理由。兩個都是「選的主題給不出字」，差別在為什麼。
enum TodayBlock: Equatable {
    /// 選的主題都學過了。
    case themesExhausted
    /// 選的主題都學過了，而且這是一個非會員、全部免費主題也都學完了：
    /// 能換的主題全部上鎖，「換幾個主題」指不到任何學得到的東西。見
    /// `FreeThemesProgress`。
    case freeThemesLearned
    /// 選的主題在目前的牌組裡沒有字。
    case noCards
}

/// 按鈕底下那一行。永遠最多一行，說的永遠是「你還能做的另一件事」。
///
/// 它接手了原本 `heroHint` 的位子。那三個 case 裡有兩個是在解釋某顆按鈕為什麼
/// 反灰 —— 按鈕併成一顆之後就沒有那回事了。
enum TodayFooter: Equatable {
    /// 正要去複習，但新字也還能學：給一個切過去的出口。
    case switchToNew
    /// 按鈕死了，唯一的出路是換主題。
    case changeThemes
    /// 按鈕死了，而能換的主題都要會員：出路是付費頁。
    case unlockAllThemes
}

/// How far a non-member is through every theme they may study — picked or not.
///
/// The selection's own numbers cannot answer this. A non-member who picked only
/// 留學生 and learned all of it still has 水果 and 臥室 to add, and 「換幾個主題」
/// is the right thing to offer. One who has learned every free theme has
/// nothing that line could lead to: each theme they could switch to is locked,
/// and the way on is membership — which 首頁 used to leave them to find for
/// themselves, through the theme picker and a padlock.
struct FreeThemesProgress: Equatable {
    /// Published cards across the free themes.
    var total: Int
    /// Cards not yet studied, counted theme by theme. Not `total − seen`: a
    /// withdrawn word leaves one theme's seen above its total, and summed, that
    /// surplus would hide another theme's unlearned words.
    var unseen: Int

    var allLearned: Bool {
        self.total > 0 && self.unseen == 0
    }
}

extension FreeThemesProgress {
    /// nil when nothing is gated: members, policy v1, and before the first
    /// entitlement sync (`StudyCategoryDefaults.liveStudyable`).
    @MainActor
    init?(studyable: [String]?, progress: ProgressStore) {
        // An empty filter means "every category" to ProgressStore, so a gate
        // that lists nothing must not be read as the whole dictionary.
        guard let studyable, !studyable.isEmpty else { return nil }
        self.init(
            total: progress.totalCount(filter: studyable),
            unseen: studyable.reduce(0) { left, theme in
                left + max(0, progress.totalCount(filter: [theme]) - progress.seenCount(filter: [theme]))
            }
        )
    }
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
        /// The 完成度 half, verbatim — *composed*, not restated.
        ///
        /// Eight of this struct's eleven fields used to be a field-for-field
        /// copy of `CompletionReadout.Inputs`, doc comments included, and
        /// `completion` below copied them across one more time. Three of the
        /// eleven are genuinely 首頁's own, and those three are what is left.
        var completion: CompletionReadout.Inputs
        var dailyGoal: Int
        var stats: StudyStats?
        /// `ProgressStore.phase == .loaded`. It was `!categoryProgress.isEmpty`,
        /// which an account with no themes answered the same way as a read
        /// that had not arrived.
        var progressLoaded: Bool
        /// Every free theme's progress, for a non-member; nil for everyone
        /// else.
        var freeThemes: FreeThemesProgress? = nil
    }

    let inputs: Inputs

    init(_ inputs: Inputs) {
        self.inputs = inputs
    }

    /// 完成度, scoped to the selection. The rule lives on `CompletionReadout`
    /// so 我's card asks the same question the same way — it used to carry its
    /// own copy, with a whole-dictionary fallback.
    var completion: CompletionReadout {
        CompletionReadout(self.inputs.completion)
    }

    // The 完成度 facts 首頁 also reasons about directly. Shortcuts, not a second
    // copy: they read straight through to the one input set.
    private var studyCategories: [String] {
        self.inputs.completion.studyCategories
    }

    private var seenInSelection: Int {
        self.inputs.completion.seenInSelection
    }

    private var totalInSelection: Int {
        self.inputs.completion.totalInSelection
    }

    var showThemePrompt: Bool {
        self.completion.showsThemePrompt
    }

    var dailyGoalReached: Bool {
        let goal = max(1, self.inputs.dailyGoal)
        return (self.inputs.stats?.todayNew ?? 0) >= goal
    }

    var reviewDisabled: Bool {
        (self.inputs.stats?.due ?? 0) == 0
    }

    /// New words still to learn within the selected themes: (total − seen)
    /// scoped to the selection, derived from progress so it tracks the
    /// selection without a stats refetch. Falls back to the global `new` count
    /// before progress loads.
    var newAvailable: Int {
        guard self.inputs.progressLoaded else { return self.inputs.stats?.new ?? 0 }
        return max(0, self.totalInSelection - self.seenInSelection)
    }

    var newBlock: TodayNewBlock {
        // No themes selected → nothing to draw new words from (review stays
        // available — it spans all studied words).
        if self.studyCategories.isEmpty { return .noThemes }
        // total == 0 with progress loaded means the selected themes have no
        // cards in the current deck — e.g. a theme with no 日文 cards yet —
        // a different dead-end from "you've learned them all".
        if self.inputs.progressLoaded, self.totalInSelection == 0 { return .noCards }
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
        self.newBlock != .none
    }

    var heading: TodayHeading {
        if self.showThemePrompt { return .noThemes }
        guard let first = self.studyCategories.first else { return .unknown }
        return .themes(firstId: first, count: self.studyCategories.count)
    }

    /// 今天這一輪會抽幾個新字：每日目標，被主題裡剩下的字數蓋住。
    ///
    /// 沒有走 `StudyQuotas.computeNewLimit`，因為走得到這裡就表示 `due == 0`，
    /// 而那個函式只在積壓超過 20 才開始削 —— 在這裡它一定回傳 goal。積壓削減
    /// 仍然成立，只是它成立的時候按鈕在複習模式，根本不報新字的數。
    var newCount: Int {
        max(0, min(self.newAvailable, max(1, self.inputs.dailyGoal)))
    }

    var call: TodayCall {
        if self.showThemePrompt { return .pickThemes }
        guard let stats = self.inputs.stats else { return .unknown }
        if stats.due > 0 { return .study(mode: .review, count: stats.due) }
        switch self.newBlock {
        case .noThemes: return .pickThemes
        case .noCards: return .blocked(.noCards)
        case .allLearned: return .blocked(self.freeThemesLearned ? .freeThemesLearned : .themesExhausted)
        // 走到這裡 `due == 0`，而 computeNewLimit 只在 due > 100 時歸零，
        // 所以這個分支到不了。真的到了，結果跟「主題給不出字」一樣。
        case .reviewBacklog: return .blocked(.themesExhausted)
        case .none: return .study(mode: .new, count: self.newCount)
        }
    }

    var footer: TodayFooter? {
        switch self.call {
        case .pickThemes, .unknown: nil
        case let .study(mode, _): mode == .review && !self.newDisabled ? .switchToNew : nil
        case .blocked(.freeThemesLearned): .unlockAllThemes
        case .blocked: .changeThemes
        }
    }

    /// A non-member has learned every word in every free theme. Waits for
    /// progress, as `newAvailable`'s scoped answer does: before it lands every
    /// count is zero, and that is not the same as everything learned.
    var freeThemesLearned: Bool {
        guard self.inputs.progressLoaded else { return false }
        return self.inputs.freeThemes?.allLearned ?? false
    }
}
