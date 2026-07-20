import Testing
@testable import Tuji

struct TodayViewHintTests {
    @Test
    func showsAdjustedNewQuotaWhenBacklogTapersGoal() {
        let adj = TodayView.newQuotaAdjustment(
            isGuest: false,
            stats: StudyStats(total: 120, seen: 40, due: 77, new: 80, todayNew: 2),
            newAvailable: 80,
            dailyGoal: 10
        )

        #expect(adj?.due == 77)
        #expect(adj?.limit == 5)
    }

    @Test
    func hidesAdjustedNewQuotaWhenBacklogIsSmall() {
        let adj = TodayView.newQuotaAdjustment(
            isGuest: false,
            stats: StudyStats(total: 120, seen: 40, due: 20, new: 80, todayNew: 2),
            newAvailable: 80,
            dailyGoal: 10
        )

        #expect(adj == nil)
    }

    @Test
    func hidesAdjustedNewQuotaWhenBacklogBlocksNewCards() {
        let adj = TodayView.newQuotaAdjustment(
            isGuest: false,
            stats: StudyStats(total: 120, seen: 40, due: 101, new: 80, todayNew: 2),
            newAvailable: 80,
            dailyGoal: 10
        )

        #expect(adj == nil)
    }

    @Test
    func hidesAdjustedNewQuotaWhenDailyGoalAlreadyReached() {
        let adj = TodayView.newQuotaAdjustment(
            isGuest: false,
            stats: StudyStats(total: 120, seen: 40, due: 77, new: 80, todayNew: 10),
            newAvailable: 80,
            dailyGoal: 10
        )

        #expect(adj == nil)
    }

    @Test
    func hidesAdjustedNewQuotaWhenNoNewWordsAvailable() {
        let adj = TodayView.newQuotaAdjustment(
            isGuest: false,
            stats: StudyStats(total: 120, seen: 120, due: 77, new: 0, todayNew: 2),
            newAvailable: 0,
            dailyGoal: 10
        )

        #expect(adj == nil)
    }
}
