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
// The CJK face is GenSenRounded 2 (ADR-0003). It is *not* set with `Font.custom`:
// that would hand Latin text to GenSenRounded's own Latin — a Source Sans
// derivative that is neither rounded nor Plus Jakarta — replacing the Latin face
// across the whole app as a side effect of fixing Chinese. Instead each token is
// a Plus Jakarta descriptor with the CJK face in its **cascade list**, so a glyph
// Plus Jakarta cannot draw falls through to GenSenRounded and nothing else moves.

import SwiftUI
import UIKit

extension Font {
    /// The word being learned; the number on a completion screen.
    static var tujiDisplay: Font {
        TujiTypeface.font(latin: "PlusJakartaSans-ExtraBold", size: 56)
    }

    /// Screen title — in the content flow, not in the navigation bar.
    static var tujiH1: Font {
        TujiTypeface.font(latin: "PlusJakartaSans-Bold", size: 34)
    }

    /// Section heading, sheet title.
    static var tujiH2: Font {
        TujiTypeface.font(latin: "PlusJakartaSans-Bold", size: 24)
    }

    /// List row primary text, button text, segmented control text.
    /// Merges the old tujiH3 (22) and tujiH4 (18) — they were never distinguishable.
    static var tujiH3: Font {
        TujiTypeface.font(latin: "PlusJakartaSans-Bold", size: 18)
    }

    /// Body copy, example sentences, descriptions.
    static var tujiBody: Font {
        TujiTypeface.font(latin: "PlusJakartaSans-Regular", size: 16)
    }

    /// Secondary explanation, row subtitles.
    static var tujiBodySm: Font {
        TujiTypeface.font(latin: "PlusJakartaSans-Regular", size: 14)
    }

    /// Badges, status labels, section overlines, tab labels.
    /// Merges the old tujiCaption and tujiOverline (both 12) and lifts them to 13.
    /// Render with `.tracking(0.5)` — the scale assumes +4% letter spacing.
    static var tujiLabel: Font {
        TujiTypeface.font(latin: "PlusJakartaSans-Bold", size: 13)
    }

    /// IPA, UID, system codes. Latin-only by definition, so no CJK cascade.
    static let tujiMono = Font.custom("JetBrainsMono-Regular", size: 13)
}

/// Resolves a token to a real font, pairing the Latin face with the CJK face for
/// the current interface language (ADR-0003).
///
/// Reads `SettingsStore` rather than caching the language in a global that
/// something has to remember to update: the read happens inside a SwiftUI body,
/// so it registers as an observation dependency and every screen re-renders with
/// the new face the moment 語言 changes. A global would have to be written at
/// exactly the right moment, and a missed write is invisible — the app would
/// simply keep rendering Japanese in Taiwanese glyph forms.
@MainActor
enum TujiTypeface {
    case tw
    case jp

    /// ja gets the JP face; every other interface language gets TW.
    ///
    /// zh-Hans knowingly gets Taiwan glyph forms — GenSenRounded has no SC face,
    /// and coverage is complete so there is no tofu, only regionally different
    /// stroke conventions. `en` has no CJK to place.
    static var current: TujiTypeface {
        SettingsStore.shared.current.uiLanguage == .ja ? .jp : .tw
    }

    static func font(latin: String, size: CGFloat) -> Font {
        let face = self.current
        // Dynamic Type is not free here. `Font.custom(_:size:)` scales with the
        // user's text size on its own; `Font(_: UIFont)` does not — it is a fixed
        // point size. Swapping one for the other would have silently frozen every
        // label in the app at the default size, so the metric is applied by hand
        // and the category joins the cache key: the same token at a different
        // text size is a different font, and a cache that ignored that would keep
        // handing back the size the app happened to launch at.
        let category = UITraitCollection.current.preferredContentSizeCategory
        let key = Key(latin: latin, size: size, face: face, category: category)
        if let hit = self.cache[key] { return hit }
        let cjk = face.name(matching: latin)
        let descriptor = UIFontDescriptor(fontAttributes: [.name: latin])
            .addingAttributes([.cascadeList: [UIFontDescriptor(fontAttributes: [.name: cjk])]])
        let base = UIFont(descriptor: descriptor, size: size)
        let font = Font(UIFontMetrics.default.scaledFont(for: base))
        self.cache[key] = font
        return font
    }

    /// Two weights are bundled, not the three ADR-0003 lists: no token asks for
    /// Medium, and an unused CJK weight is 31 MB of nothing. Display is set in
    /// ExtraBold and takes Bold here — GenSenRounded's Heavy would cost another
    /// 30 MB for one token.
    private func name(matching latin: String) -> String {
        let weight = latin.contains("Bold") ? "B" : "R"
        return switch self {
        case .tw: "GenSenRounded2TW-\(weight)"
        case .jp: "GenSenRounded2JP-\(weight)"
        }
    }

    private struct Key: Hashable {
        let latin: String
        let size: CGFloat
        let face: TujiTypeface
        let category: UIContentSizeCategory
    }

    /// Building a descriptor with a cascade list is not free, and these are
    /// evaluated on every body pass of every screen.
    private static var cache: [Key: Font] = [:]
}
