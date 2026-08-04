// Motion — 3 durations and exactly one curve.
//
// New in the 紙與墨 system. The direction is carried by rhythm rather than
// decoration, so motion has to be held down: without a ceiling it drifts toward
// the bouncy, reward-animation register the design explicitly rules out.
//
// **One curve: `easeOut`. No spring, no bounce, no overshoot.**

import SwiftUI

enum Motion {
    /// State change: press, selection, chip inversion.
    static let d1: Double = 0.12
    /// Enter/exit: sheets, navigation pushes, title fade-in.
    static let d2: Double = 0.22
    /// The only animation allowed to be *watched*: a progress value changing,
    /// mastery climbing, a skeleton breathing.
    static let d3: Double = 0.4

    static func ease(_ duration: Double) -> Animation {
        .easeOut(duration: duration)
    }

    /// `d3` motion is the only kind a user is meant to follow, so it is also the
    /// only kind that must be suppressed rather than shortened under
    /// Reduce Motion — the value should jump, not race.
    static func ease(_ duration: Double, reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : .easeOut(duration: duration)
    }
}
