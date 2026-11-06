// Pins 首頁's decisions — the heading, the one button, the line under it,
// the 學新字 gate, the 主題進度 fraction.
//
// Before `TodayDecisions` existed these were `private var`s on an 802-line
// `View`, so the only one under test was the single rule someone had already
// lifted into a `static func`.
//
// 墨塊收成一顆按鈕之後，`subtitle` 的七個 case 和 `heroHint` 的三個換成了
// `heading` / `call` / `footer`，這裡跟著換。`quotaAdjustment` 和它的兩個測試
// 一起刪掉了：它只服務那行提示，而提示沒了 —— 底下那條削減規則本身由
// `StudyQuotasTests` 直接盯著，沒有少掉覆蓋。
//
// The decisions return enums rather than copy, so none of this needs a bundle
// or a locale.

import Testing
@testable import Tuji

struct TodayDecisionsTests {
    private func inputs(
        settingsLoaded: Bool = true,
        studyCategories: [String] = ["kitchen"],
        dailyGoal: Int = 10,
        stats: StudyStats? = StudyStats(total: 120, seen: 40, due: 0, new: 80, todayNew: 0),
        progressLoaded: Bool = true,
        seenInSelection: Int = 40,
        totalInSelection: Int = 120,
        dictionaryCount: Int = 480,
        dictionaryCountInSelection: Int = 60
    )
        -> TodayDecisions.Inputs
    {
        TodayDecisions.Inputs(
            completion: CompletionReadout.Inputs(
                settingsLoaded: settingsLoaded,
                studyCategories: studyCategories,
                seenInSelection: seenInSelection,
                totalInSelection: totalInSelection,
                dictionaryCount: dictionaryCount,
                dictionaryCountInSelection: dictionaryCountInSelection
            ),
            dailyGoal: dailyGoal,
            stats: stats,
            progressLoaded: progressLoaded
        )
    }

    // MARK: - 標題

    @Test("標題報第一個主題的 id 和總數 —— 名字是 View 去查的")
    func headingNamesTheFirstThemeAndCounts() {
        let d = TodayDecisions(self.inputs(studyCategories: ["kitchen", "station", "fruit"]))
        #expect(d.heading == .themes(firstId: "kitchen", count: 3))
    }

    /// 空的主題清單在 settings 落地之前什麼都不代表，所以標題不能說「還沒選」。
    @Test("settings 還沒到的時候，標題不宣稱任何事")
    func headingWaitsForSettings() {
        #expect(TodayDecisions(self.inputs(settingsLoaded: false, studyCategories: [])).heading == .unknown)
        #expect(TodayDecisions(self.inputs(studyCategories: [])).heading == .noThemes)
    }

    // MARK: - 那顆按鈕

    /// 兩顆按鈕併成一顆之後，這條是整個合併最重的一個決定：有字要複習的人
    /// 不能再自己選今天只學新字。
    @Test("有字要複習就複習，不管新字還剩多少")
    func callPrefersReview() {
        let d = TodayDecisions(self.inputs(
            stats: StudyStats(total: 120, seen: 40, due: 7, new: 80, todayNew: 20)
        ))
        #expect(d.call == .study(mode: .review, count: 7))
    }

    @Test("沒字要複習就學新字，數量是每日目標蓋在主題剩下的字數上")
    func callFallsToNewCappedByGoalAndRemainder() {
        let plenty = TodayDecisions(self.inputs(
            dailyGoal: 10,
            stats: StudyStats(total: 120, seen: 40, due: 0, new: 80, todayNew: 0)
        ))
        #expect(plenty.call == .study(mode: .new, count: 10))

        let nearlyDone = TodayDecisions(self.inputs(
            dailyGoal: 10,
            stats: StudyStats(total: 120, seen: 117, due: 0, new: 3, todayNew: 0),
            seenInSelection: 117
        ))
        #expect(nearlyDone.call == .study(mode: .new, count: 3))
    }

    /// 一個在第一次抓取落地前就報出來的數量是猜的。
    @Test("stats 還沒到就不報數字")
    func callWaitsForStats() {
        #expect(TodayDecisions(self.inputs(stats: nil)).call == .unknown)
    }

    @Test("主題學完了，按鈕死掉，唯一的出路是換主題")
    func callBlocksWhenThemesAreExhausted() {
        let d = TodayDecisions(self.inputs(
            stats: StudyStats(total: 120, seen: 120, due: 0, new: 0, todayNew: 0),
            seenInSelection: 120
        ))
        #expect(d.call == .blocked(.themesExhausted))
        #expect(d.footer == .changeThemes)
    }

    @Test("沒選主題的時候，按鈕自己就是那張提示卡")
    func callAsksForThemes() {
        let d = TodayDecisions(self.inputs(studyCategories: []))
        #expect(d.call == .pickThemes)
        #expect(d.footer == nil)
    }

    @Test("an empty theme list only means 'pick themes' once settings have loaded")
    func themePromptWaitsForSettings() {
        #expect(!TodayDecisions(self.inputs(settingsLoaded: false, studyCategories: [])).showThemePrompt)
        #expect(TodayDecisions(self.inputs(studyCategories: [])).showThemePrompt)
    }

    // MARK: - 主題進度 denominator

    @Test("the denominator describes the selection, not the whole dictionary")
    func dexTotalFallsBackWithinTheSelection() {
        // The regression this guards: themes that hold nothing on the server
        // used to read 「0 / 480」 — a denominator describing a selection
        // nobody made.
        let d = TodayDecisions(self.inputs(
            totalInSelection: 0,
            dictionaryCount: 480,
            dictionaryCountInSelection: 60
        ))
        #expect(d.completion.total == 60)
    }

    @Test("with no themes picked the fraction reads 0/0, matching the empty state")
    func dexIsZeroWhileThemesArePending() {
        let d = TodayDecisions(self.inputs(studyCategories: [], totalInSelection: 99))
        #expect(d.completion.seen == 0)
        #expect(d.completion.total == 0)
    }

    @Test("with themes picked but nothing selected locally the whole dictionary is the fallback")
    func dexTotalUsesDictionaryOnlyWhenNothingIsSelected() {
        // Before settings arrive there is no theme prompt, so an empty selection
        // reaches the dictionary-wide fallback — the one case where 480 is the
        // right answer.
        let d = TodayDecisions(self.inputs(
            settingsLoaded: false,
            studyCategories: [],
            totalInSelection: 0,
            dictionaryCount: 480
        ))
        #expect(d.completion.total == 480)
    }

    // MARK: - 學新字 gate

    @Test("no themes is a different dead-end from no cards")
    func blockDistinguishesNoThemesFromNoCards() {
        #expect(TodayDecisions(self.inputs(studyCategories: [])).newBlock == .noThemes)
        #expect(
            TodayDecisions(self.inputs(seenInSelection: 0, totalInSelection: 0)).newBlock
                == .noCards
        )
    }

    @Test("everything learned in the selected themes says so")
    func blockReportsAllLearned() {
        let d = TodayDecisions(self.inputs(seenInSelection: 120, totalInSelection: 120))
        #expect(d.newAvailable == 0)
        #expect(d.newBlock == .allLearned)
    }

    @Test("a crowded review backlog greys 學新字 rather than serving an empty queue")
    func blockReportsReviewBacklog() {
        let d = TodayDecisions(self.inputs(
            stats: StudyStats(total: 120, seen: 40, due: 101, new: 80, todayNew: 0)
        ))
        #expect(d.newBlock == .reviewBacklog)
        #expect(d.newDisabled)
    }

    @Test("before progress loads the global new count stands in")
    func newAvailableFallsBackBeforeProgressLoads() {
        let d = TodayDecisions(self.inputs(progressLoaded: false))
        #expect(d.newAvailable == 80)
    }

    @Test("review is disabled exactly when nothing is due")
    func reviewGate() {
        #expect(TodayDecisions(self.inputs()).reviewDisabled)
        #expect(
            !TodayDecisions(self.inputs(
                stats: StudyStats(total: 120, seen: 40, due: 3, new: 80, todayNew: 0)
            )).reviewDisabled
        )
    }

    // MARK: - 底下那一行

    /// 這一行接手了 `heroHint` 的位子，但問的是另一個問題。舊的三個 case 有
    /// 兩個在解釋某顆按鈕為什麼反灰 —— 按鈕併成一顆之後就沒有那回事了。
    @Test("要去複習、而且新字也還能學，才給一條切過去的出口")
    func footerOffersNewOnlyBesideReview() {
        let d = TodayDecisions(self.inputs(
            stats: StudyStats(total: 120, seen: 40, due: 7, new: 80, todayNew: 0)
        ))
        #expect(d.call == .study(mode: .review, count: 7))
        #expect(d.footer == .switchToNew)
    }

    @Test("已經在學新字的時候沒有這一行 —— 沒有別的可以改")
    func footerIsSilentInNewMode() {
        let d = TodayDecisions(self.inputs(
            stats: StudyStats(total: 120, seen: 40, due: 0, new: 80, todayNew: 0)
        ))
        #expect(d.call == .study(mode: .new, count: 10))
        #expect(d.footer == nil)
    }

    /// 出口得走得通。主題裡的字都學過了，「學新字」就是一條死路。
    @Test("新字被擋的時候不給出口")
    func footerIsSilentWhenNewIsBlocked() {
        let d = TodayDecisions(self.inputs(
            stats: StudyStats(total: 120, seen: 120, due: 7, new: 0, todayNew: 0),
            seenInSelection: 120
        ))
        #expect(d.call == .study(mode: .review, count: 7))
        #expect(d.newDisabled)
        #expect(d.footer == nil)
    }
}
