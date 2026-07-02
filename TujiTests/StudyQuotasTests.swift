// StudyQuotas mirrors lib/scheduling.ts — these tests pin the taper
// boundaries so a client-side drift from the backend shows up in CI.

import Testing
@testable import Tuji

struct StudyQuotasTests {
    @Test
    func fullGoalWhileBacklogSmall() {
        #expect(StudyQuotas.computeNewLimit(goal: 8, due: 0) == 8)
        #expect(StudyQuotas.computeNewLimit(goal: 8, due: 20) == 8)
    }

    @Test
    func tapersAsBacklogGrows() {
        #expect(StudyQuotas.computeNewLimit(goal: 8, due: 21) == 6)
        #expect(StudyQuotas.computeNewLimit(goal: 8, due: 50) == 6)
        #expect(StudyQuotas.computeNewLimit(goal: 8, due: 51) == 4)
        #expect(StudyQuotas.computeNewLimit(goal: 8, due: 100) == 4)
    }

    @Test
    func zeroNewCardsOnHeavyBacklog() {
        #expect(StudyQuotas.computeNewLimit(goal: 8, due: 101) == 0)
        #expect(StudyQuotas.computeNewLimit(goal: 100, due: 500) == 0)
    }
}
