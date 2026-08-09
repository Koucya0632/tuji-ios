// Border widths — 3 steps.
//
// New in the 紙與墨 system. With no corner radius and no shadow, focus and
// selection need a signal that does not depend on shape, so it comes from a
// stroke instead.
//
// Default state has no border. A border appears only for focus, selection, or
// warning — if a resting element has one, something is wrong.

import CoreGraphics

enum Border {
    /// The `tujiRule` separator. The only "line" in the app.
    static let bw1: CGFloat = 1
    /// Focus ring (`tujiCurrent`), check-mark stroke.
    static let bw2: CGFloat = 2
    /// Selection indicator: tab top edge, multi-select row leading edge, sheet
    /// top edge, status label leading edge, progress bars.
    static let bw3: CGFloat = 3
}
