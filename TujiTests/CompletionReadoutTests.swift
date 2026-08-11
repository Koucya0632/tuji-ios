// Pins 完成度 — the seen/total/ratio rule that 首頁's hero and 我's completion
// card now share.
//
// Each of the first three tests is a case where the two screens used to
// disagree, because 我 carried its own copy of the rule from before the
// denominator fix and without a guest branch at all.

import Testing
@testable import Tuji

struct CompletionReadoutTests {
    private func inputs(
        isGuest: Bool = false,
        settingsLoaded: Bool = true,
        studyCategories: [String] = ["kitchen"],
        guestLearnedCount: Int = 0,
        seenInSelection: Int = 40,
        totalInSelection: Int = 120,
        dictionaryCount: Int = 480,
        dictionaryCountInSelection: Int = 60
    )
        -> CompletionReadout.Inputs
    {
        CompletionReadout.Inputs(
            isGuest: isGuest,
            settingsLoaded: settingsLoaded,
            studyCategories: studyCategories,
            guestLearnedCount: guestLearnedCount,
            seenInSelection: seenInSelection,
            totalInSelection: totalInSelection,
            dictionaryCount: dictionaryCount,
            dictionaryCountInSelection: dictionaryCountInSelection
        )
    }

    // MARK: - The three divergences

    @Test("a guest's progress is the local learned set, not the empty server rows")
    func guestCountsWhatIsOnTheDevice() {
        // 我 used to read the server's seen count for guests — always 0 — and
        // print 「0% · 已學 0 / 共 480 字」 to someone 首頁 credited with 37.
        let readout = CompletionReadout(
            self.inputs(
                isGuest: true,
                studyCategories: [],
                guestLearnedCount: 37,
                seenInSelection: 0,
                totalInSelection: 0
            )
        )
        #expect(readout.seen == 37)
        #expect(readout.total == 480)
    }

    @Test("the denominator describes the selection, not the whole dictionary")
    func fallbackStaysWithinTheSelection() {
        // Themes that hold no published cards (自定義 + 物見): the server has
        // no rows, so the fallback runs. It must stay scoped.
        let readout = CompletionReadout(
            self.inputs(
                studyCategories: ["custom", "community"],
                seenInSelection: 0,
                totalInSelection: 0,
                dictionaryCountInSelection: 12
            )
        )
        #expect(readout.total == 12)
        #expect(readout.scope == .selectedThemes)
    }

    @Test("with no themes picked the fraction reads 0/0, not a whole-catalog number")
    func noSelectionIsPending() {
        let readout = CompletionReadout(
            self.inputs(studyCategories: [], seenInSelection: 300, totalInSelection: 480)
        )
        #expect(readout.seen == 0)
        #expect(readout.total == 0)
        #expect(readout.scope == .pending)
        #expect(readout.percent == 0)
    }

    // MARK: - Fallback ladder

    @Test("the server's count wins whenever it has one")
    func serverTotalWins() {
        let readout = CompletionReadout(self.inputs())
        #expect(readout.seen == 40)
        #expect(readout.total == 120)
    }

    @Test("the whole dictionary stands in only when nothing is selected")
    func wholeDictionaryOnlyWithoutASelection() {
        // Settings have not arrived, so an empty theme list means nothing yet —
        // this is not the 選擇主題 prompt, it is "we don't know".
        let readout = CompletionReadout(
            self.inputs(
                settingsLoaded: false,
                studyCategories: [],
                seenInSelection: 0,
                totalInSelection: 0
            )
        )
        #expect(readout.total == 480)
        #expect(readout.scope == .wholeDictionary)
    }

    // MARK: - Ratio

    @Test("a withdrawn word can leave seen > total, and the ratio still stops at 1")
    func ratioClamps() {
        // seen counts studied words; total counts *published* cards. Two of the
        // four hand-written copies of this expression skipped the clamp, which
        // printed 「103%」 beside a bar pinned at full.
        let readout = CompletionReadout(
            self.inputs(seenInSelection: 124, totalInSelection: 120)
        )
        #expect(readout.ratio == 1)
        #expect(readout.percent == 100)
    }

    @Test("a zero denominator is zero, not a division by zero")
    func ratioIsZeroSafe() {
        #expect(CompletionReadout.ratio(seen: 0, total: 0) == 0)
        #expect(CompletionReadout.ratio(seen: 5, total: 0) == 0)
    }

    @Test("the percentage is derived from the ratio, so it cannot disagree with the bar")
    func percentFollowsRatio() {
        let readout = CompletionReadout(
            self.inputs(seenInSelection: 40, totalInSelection: 120)
        )
        #expect(readout.percent == 33)
        #expect(readout.ratio == CompletionReadout.ratio(seen: 40, total: 120))
    }

    // MARK: - Theme prompt

    @Test("an empty theme list only means 'pick themes' once settings have loaded")
    func themePromptWaitsForSettings() {
        #expect(
            !CompletionReadout(self.inputs(settingsLoaded: false, studyCategories: []))
                .showsThemePrompt
        )
        #expect(
            CompletionReadout(self.inputs(settingsLoaded: true, studyCategories: []))
                .showsThemePrompt
        )
    }

    @Test("a guest is never prompted to pick themes")
    func guestsAreNotPrompted() {
        let readout = CompletionReadout(self.inputs(isGuest: true, studyCategories: []))
        #expect(!readout.showsThemePrompt)
    }
}
