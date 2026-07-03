import Testing
@testable import Tuji

struct TodayViewHintTests {
    @Test
    func showsAdjustedNewQuotaWhenBacklogTapersGoal() {
        let hint = TodayView.newQuotaAdjustmentHintText(
            isGuest: false,
            stats: StudyStats(total: 120, seen: 40, due: 77, new: 80, todayNew: 2),
            newAvailable: 80,
            dailyGoal: 10
        )

        #expect(hint == "因為還有 77 個字要複習，今天新字先調整為 5 個。")
    }

    @Test
    func hidesAdjustedNewQuotaWhenBacklogIsSmall() {
        let hint = TodayView.newQuotaAdjustmentHintText(
            isGuest: false,
            stats: StudyStats(total: 120, seen: 40, due: 20, new: 80, todayNew: 2),
            newAvailable: 80,
            dailyGoal: 10
        )

        #expect(hint == nil)
    }

    @Test
    func hidesAdjustedNewQuotaWhenBacklogBlocksNewCards() {
        let hint = TodayView.newQuotaAdjustmentHintText(
            isGuest: false,
            stats: StudyStats(total: 120, seen: 40, due: 101, new: 80, todayNew: 2),
            newAvailable: 80,
            dailyGoal: 10
        )

        #expect(hint == nil)
    }

    @Test
    func hidesAdjustedNewQuotaWhenDailyGoalAlreadyReached() {
        let hint = TodayView.newQuotaAdjustmentHintText(
            isGuest: false,
            stats: StudyStats(total: 120, seen: 40, due: 77, new: 80, todayNew: 10),
            newAvailable: 80,
            dailyGoal: 10
        )

        #expect(hint == nil)
    }

    @Test
    func hidesAdjustedNewQuotaWhenNoNewWordsAvailable() {
        let hint = TodayView.newQuotaAdjustmentHintText(
            isGuest: false,
            stats: StudyStats(total: 120, seen: 120, due: 77, new: 0, todayNew: 2),
            newAvailable: 0,
            dailyGoal: 10
        )

        #expect(hint == nil)
    }
}
