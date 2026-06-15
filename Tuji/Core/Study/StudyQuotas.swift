// Daily-quota math for the study flow. Mirrors lib/scheduling.ts on
// the backend: new-card quota tapers off as the review backlog grows
// so users dig out of due cards before piling on more new ones.
//
// Shared between TodayView (button disable state) and StudyLauncherView
// (queue sizing) so both surfaces stay in sync.

import Foundation

enum StudyQuotas {
    static func computeNewLimit(goal: Int, due: Int) -> Int {
        switch due {
        case ...20: goal
        case 21...50: Int(Double(goal) * 0.75)
        case 51...100: Int(Double(goal) * 0.5)
        default: 0
        }
    }
}
