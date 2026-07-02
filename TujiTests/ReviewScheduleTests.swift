// ReviewSchedule's tolerant ISO parser exists because the backend emits
// fractional seconds that Foundation's default .iso8601 decoder rejects —
// these tests pin both accepted forms so a "cleanup" doesn't regress it.

import Foundation
import Testing
@testable import Tuji

struct ReviewScheduleTests {
    @Test
    func parsesFractionalSecondsISO() {
        #expect(ReviewSchedule.parseISO("2026-07-02T10:00:00.123Z") != nil)
    }

    @Test
    func parsesPlainISO() {
        #expect(ReviewSchedule.parseISO("2026-07-02T10:00:00Z") != nil)
    }

    @Test
    func rejectsGarbage() {
        #expect(ReviewSchedule.parseISO("not-a-date") == nil)
        #expect(ReviewSchedule.parseISO("") == nil)
    }

    @Test
    func overdueAtOrBeforeNow() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        #expect(ReviewSchedule.isOverdue(now, now: now))
        #expect(ReviewSchedule.isOverdue(now.addingTimeInterval(-1), now: now))
        #expect(!ReviewSchedule.isOverdue(now.addingTimeInterval(1), now: now))
    }

    @Test
    func countdownShowsDueLabelWhenOverdue() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        #expect(ReviewSchedule.countdownLabel(until: now, now: now) == "復習期")
    }
}
