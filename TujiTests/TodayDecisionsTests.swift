// Pins 首頁's decisions — the subtitle, the 學新字 gate, the 主題進度 fraction.
//
// Before `TodayDecisions` existed these were `private var`s on an 802-line
// `View`, so the only one under test was the single rule someone had already
// lifted into a `static func`. The five quota tests below are that file,
// carried over unchanged; everything after them is what could not be reached
// at all.
//
// The decisions return enums rather than copy, so none of this needs a bundle
// or a locale.

import Testing
@testable import Tuji

struct TodayDecisionsTests {
    private func inputs(
        isGuest: Bool = false,
        settingsLoaded: Bool = true,
        studyCategories: [String] = ["kitchen"],
        dailyGoal: Int = 10,
        stats: StudyStats? = StudyStats(total: 120, seen: 40, due: 0, new: 80, todayNew: 0),
        guestLearnedCount: Int = 0,
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
                isGuest: isGuest,
                settingsLoaded: settingsLoaded,
                studyCategories: studyCategories,
                guestLearnedCount: guestLearnedCount,
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

    // MARK: - Quota adjustment (carried over from TodayViewHintTests)

    @Test
    func showsAdjustedNewQuotaWhenBacklogTapersGoal() {
        let adj = TodayDecisions(self.inputs(
            stats: StudyStats(total: 120, seen: 40, due: 77, new: 80, todayNew: 2)
        )).quotaAdjustment

        #expect(adj?.due == 77)
        #expect(adj?.limit == 5)
    }

    @Test
    func hidesAdjustedNewQuotaWhenBacklogIsSmall() {
        let adj = TodayDecisions(self.inputs(
            stats: StudyStats(total: 120, seen: 40, due: 20, new: 80, todayNew: 2)
        )).quotaAdjustment

        #expect(adj == nil)
    }

    @Test
    func hidesAdjustedNewQuotaWhenBacklogBlocksNewCards() {
        let adj = TodayDecisions(self.inputs(
            stats: StudyStats(total: 120, seen: 40, due: 101, new: 80, todayNew: 2)
        )).quotaAdjustment

        #expect(adj == nil)
    }

    @Test
    func hidesAdjustedNewQuotaWhenDailyGoalAlreadyReached() {
        let adj = TodayDecisions(self.inputs(
            stats: StudyStats(total: 120, seen: 40, due: 77, new: 80, todayNew: 10)
        )).quotaAdjustment

        #expect(adj == nil)
    }

    @Test
    func hidesAdjustedNewQuotaWhenNoNewWordsAvailable() {
        let adj = TodayDecisions(self.inputs(
            stats: StudyStats(total: 120, seen: 120, due: 77, new: 0, todayNew: 2),
            seenInSelection: 120,
            totalInSelection: 120
        )).quotaAdjustment

        #expect(adj == nil)
    }

    // MARK: - Subtitle

    @Test("a review backlog outranks everything else the line could say")
    func subtitlePrefersReviewBacklog() {
        let d = TodayDecisions(self.inputs(
            stats: StudyStats(total: 120, seen: 40, due: 7, new: 80, todayNew: 20)
        ))
        #expect(d.subtitle == .reviewDue(count: 7))
    }

    @Test("the goal-reached line cannot contradict the 達成 badge")
    func subtitleGoalReachedBeatsNewProgress() {
        // todayNew(12) >= goal(10) so the badge is showing; the line must agree
        // rather than saying 「今天已學 12 個新字，繼續加油」.
        let d = TodayDecisions(self.inputs(
            stats: StudyStats(total: 120, seen: 40, due: 0, new: 80, todayNew: 12)
        ))
        #expect(d.dailyGoalReached)
        #expect(d.subtitle == .goalReached)
    }

    @Test("no verdict is offered before stats arrive")
    func subtitleWaitsForStats() {
        #expect(TodayDecisions(self.inputs(stats: nil)).subtitle == .unknown)
    }

    @Test("a guest is told what they have, or where to start")
    func subtitleForGuests() {
        #expect(
            TodayDecisions(self.inputs(isGuest: true, guestLearnedCount: 4)).subtitle
                == .guestLearned(count: 4)
        )
        #expect(
            TodayDecisions(self.inputs(isGuest: true, guestLearnedCount: 0)).subtitle
                == .guestBrowsing
        )
    }

    @Test("an empty theme list only means 'pick themes' once settings have loaded")
    func themePromptWaitsForSettings() {
        #expect(!TodayDecisions(self.inputs(settingsLoaded: false, studyCategories: [])).showThemePrompt)
        #expect(TodayDecisions(self.inputs(studyCategories: [])).showThemePrompt)
        // A guest never picks themes.
        #expect(!TodayDecisions(self.inputs(isGuest: true, studyCategories: [])).showThemePrompt)
    }

    // MARK: - 主題進度 denominator

    @Test("the denominator describes the selection, not the whole dictionary")
    func dexTotalFallsBackWithinTheSelection() {
        // The regression this guards: a guest whose themes hold nothing on the
        // server used to read 「0 / 480」 — a denominator describing a selection
        // nobody made.
        let d = TodayDecisions(self.inputs(
            isGuest: true,
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
        // Guests skip showThemePrompt, so an empty selection reaches the
        // dictionary-wide fallback — the one case where 480 is the right answer.
        let d = TodayDecisions(self.inputs(
            isGuest: true,
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

    @Test("a guest is never told why 學新字 is blocked")
    func guestsGetNoBlockReason() {
        // Guests can't study new words at all; the prompt to sign in lives
        // elsewhere, so surfacing a reason here would be noise.
        let d = TodayDecisions(self.inputs(isGuest: true, studyCategories: []))
        #expect(d.newBlock == .none)
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
        #expect(
            TodayDecisions(self.inputs(
                isGuest: true,
                stats: StudyStats(total: 120, seen: 40, due: 3, new: 80, todayNew: 0)
            )).reviewDisabled
        )
    }

    // MARK: - Which hint speaks

    /// The precedence lived in a `private var` on `TodayView`, next to a second,
    /// hand-written copy of the "wait for stats" guard. Nothing could reach it.
    @Test
    func aBlockedNewStageOutranksEverythingElse() {
        // Themes selected, none of their cards left → .allLearned, and a due
        // count of 0 would otherwise say 沒有要複習的字.
        let d = TodayDecisions(self.inputs(
            stats: StudyStats(total: 120, seen: 120, due: 0, new: 0, todayNew: 0),
            seenInSelection: 120,
            totalInSelection: 120
        ))
        #expect(d.newBlock == .allLearned)
        #expect(d.heroHint == .newBlocked)
    }

    /// Nothing to review is the last thing said, not the first.
    @Test
    func anEmptyReviewQueueSpeaksOnlyWhenNothingElseDoes() {
        let d = TodayDecisions(self.inputs(
            stats: StudyStats(total: 120, seen: 40, due: 0, new: 80, todayNew: 0)
        ))
        #expect(d.reviewDisabled)
        #expect(d.heroHint == .nothingToReview)
    }

    /// A hint about today's numbers, shown before today's numbers exist, is a
    /// guess. `reviewDisabled` is already true for a nil `stats` (due == 0), so
    /// without this guard the hero would claim there is nothing to review while
    /// the request was still in the air.
    @Test
    func noHintSpeaksBeforeStatsArrive() {
        let d = TodayDecisions(self.inputs(stats: nil))
        #expect(d.reviewDisabled)
        #expect(d.heroHint == nil)
    }

    /// A guest's verdict is `.nothingToReview` — `reviewDisabled` is true for
    /// them by definition — and that is *unreachable*, not wrong: the hero
    /// swaps its whole CTA block for 建立帳號，開始學習 before any hint renders.
    ///
    /// Stated rather than asserted-away, because the next reader of
    /// `heroHint` will wonder, and because it is the kind of thing that stops
    /// being unreachable the moment someone gives guests a CTA row.
    @Test
    func aGuestsVerdictIsNeverRendered() {
        #expect(TodayDecisions(self.inputs(isGuest: true)).heroHint == .nothingToReview)
    }

    /// Picking no themes is answered by the theme prompt, not by a caption.
    @Test
    func noThemesSelectedIsNotAHint() {
        let d = TodayDecisions(self.inputs(
            studyCategories: [],
            stats: StudyStats(total: 120, seen: 40, due: 3, new: 80, todayNew: 0)
        ))
        #expect(d.newBlock == .noThemes)
        #expect(d.heroHint == nil)
    }
}
