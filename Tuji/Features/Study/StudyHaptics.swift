// The taps a study session answers with, held and kept warm.
//
// 複習 held two primed impact generators; 學新字 built a fresh
// `UINotificationFeedbackGenerator` at every resolution and a fresh
// `UIImpactFeedbackGenerator` in `TilesView` at every tile. The difference is
// not taste. A generator built at the moment of the tap has to wake the Taptic
// Engine first, and that wake is the slow part: the buzz lands well after the
// row has already moved, which reads as the whole reaction being late even
// though the animation starts in the first frame after the tap (measured on
// 複習). `prime()` keeps the engine warm across the window where an answer is
// likely, and the system lets the readiness lapse on its own after a few
// seconds, so priming is cheap and idempotent.

import UIKit

@MainActor
final class StudyHaptics {
    private let light = UIImpactFeedbackGenerator(style: .light)
    private let medium = UIImpactFeedbackGenerator(style: .medium)
    private let notification = UINotificationFeedbackGenerator()

    /// Warm the engine for the tap that is coming.
    func prime() {
        self.light.prepare()
        self.medium.prepare()
        self.notification.prepare()
    }

    /// A tap that landed: a right answer, a rating, a tile placed.
    func soft() {
        self.light.impactOccurred()
    }

    /// A tap that did not: a wrong option, a ruled-out pick.
    func firm() {
        self.medium.impactOccurred()
    }

    /// A stage cleared.
    func success() {
        self.notification.notificationOccurred(.success)
    }

    /// A stage missed.
    func warning() {
        self.notification.notificationOccurred(.warning)
    }
}
