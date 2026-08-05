// Corner radius — 2 steps, and one of them is zero.
//
// Rounded rectangles are iOS's strongest visual fingerprint, and the old default
// (14) was exactly the system inset-grouped list radius. Zeroing it is what stops
// the app reading as a stock iOS app.
//
// `rPill` is reserved for the three things that "speak": avatars (a person),
// status dots (a live signal), and the mascot's speech bubble. Roundness is
// therefore unique on screen, and shares its geometry with the cat.

import CoreGraphics

enum Radius {
    /// Everything structural: lists, buttons, inputs, sheets, tab bar, image
    /// containers, badges, chips, segmented controls, dialogs.
    static let r0: CGFloat = 0
    /// Avatars, status dots, the mascot's speech bubble. Nothing else.
    static let rPill: CGFloat = 999
}
