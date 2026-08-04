// Font tokens — 8 steps.
// no_font_custom_outside_theme lint rule keeps Font.custom restricted here.
//
// ⚠️ The names were reused with different sizes (old tujiBody was 14, new is 16;
// old tujiH3 was 22, new is 18). Call sites were migrated by *role*, not by name.
//
// Removed 12pt entirely: CJK strokes merge at that size, and the 12 → 14 step was
// too small to survive Dynamic Type scaling — the hierarchy collapsed when the
// user enlarged text. Smallest size in the system is now 13.
//
// **Family swap is deliberately not done yet.** The target is GenSenRounded (CJK)
// + Gabarito (Latin), but neither is bundled, and `Font.custom` silently falls back
// to the *system regular* face when a family is missing — which would drop every
// weight in the app at once. Plus Jakarta Sans stays until the .otf files land
// (see ADR-0003); only the size scale changes now, so each commit renders correctly.

import SwiftUI

extension Font {
    /// The word being learned; the number on a completion screen.
    static let tujiDisplay = Font.custom("PlusJakartaSans-ExtraBold", size: 56)
    /// Screen title — in the content flow, not in the navigation bar.
    static let tujiH1 = Font.custom("PlusJakartaSans-Bold", size: 34)
    /// Section heading, sheet title.
    static let tujiH2 = Font.custom("PlusJakartaSans-Bold", size: 24)
    /// List row primary text, button text, segmented control text.
    /// Merges the old tujiH3 (22) and tujiH4 (18) — they were never distinguishable.
    static let tujiH3 = Font.custom("PlusJakartaSans-Bold", size: 18)
    /// Body copy, example sentences, descriptions.
    static let tujiBody = Font.custom("PlusJakartaSans-Regular", size: 16)
    /// Secondary explanation, row subtitles.
    static let tujiBodySm = Font.custom("PlusJakartaSans-Regular", size: 14)
    /// Badges, status labels, section overlines, tab labels.
    /// Merges the old tujiCaption and tujiOverline (both 12) and lifts them to 13.
    /// Render with `.tracking(0.5)` — the scale assumes +4% letter spacing.
    static let tujiLabel = Font.custom("PlusJakartaSans-Bold", size: 13)
    /// IPA, UID, system codes.
    static let tujiMono = Font.custom("JetBrainsMono-Regular", size: 13)
}
