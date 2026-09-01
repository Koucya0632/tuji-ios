// Spacing scale — 6 steps.
//
// The old scale had 13 steps, which is the same as having none: any value can be
// found somewhere in it, so a layout never has to make a decision and the page
// ends up with no rhythm. Six steps force every gap to be a choice.
//
// ⚠️ The names were reused with different values (old s3 was 12, new s3 is 16).
// Call sites were migrated by *value*, not by name — never assume a `Space.sN`
// written before 2026-08 means what it means now.
//
// Two hard rules:
//   • Page margin is always `s4` (24). There is no second horizontal boundary in
//     the app — with cards gone, content aligns straight to it, and that line is
//     the skeleton the whole layout hangs on.
//   • At most 4 distinct spacing values per screen. More than that means the
//     hierarchy has not been worked out.

import CoreGraphics

/// `nonisolated` because the scale has to be readable from layout-time code.
/// The project defaults to MainActor isolation, and `Shape.path(in:)` — where
/// `GlossCalloutShape` measures its caret — is not on the main actor.
nonisolated enum Space {
    static let s1: CGFloat = 4
    static let s2: CGFloat = 8
    static let s3: CGFloat = 16
    /// Page margin. The one horizontal boundary in the app.
    static let s4: CGFloat = 24
    /// Between sections.
    static let s5: CGFloat = 40
    static let s6: CGFloat = 64
}
