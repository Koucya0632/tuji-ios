// Reference-counted flag for "user is inside a focused study session".
// MainTabsView hides the TujiTabBar and drops its 78pt bottom safeAreaInset
// while this is active, reclaiming vertical room for the hero image.
//
// Counter (not bool) so the chain StudyLauncher → ReviewFlow/NewFlow →
// CompleteView/MilestoneView stays "active" across in-flight transitions
// (one view's onDisappear fires roughly when the next view's onAppear
// fires; without a counter a brief 0-state lets the bar flash back).

import Foundation
import Observation

@MainActor
@Observable
final class StudyFocus {
    static let shared = StudyFocus()

    private var counter: Int = 0
    var active: Bool {
        counter > 0
    }

    private init() {}

    func enter() {
        counter += 1
    }

    func exit() {
        counter = max(0, counter - 1)
    }
}
