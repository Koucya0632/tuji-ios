// Color tokens — 紙與墨 (Paper & Ink).
// Hex literals only allowed in this file (see .swiftlint.yml no_hex_color_outside_theme).
//
// The system has exactly five meanings, and every colour belongs to one of them.
// A colour that cannot be written into one of these sentences does not enter the system:
//
//   紙 (paper) — the ground. Three steps, expressing region hierarchy.
//   墨 (ink)   — text, and "this one is selected / this one is primary".
//   瞳 (eye)   — 現在. Where the next step is, where you are, what is running.
//   teal       — 你的積累. Mastery, completion, learned, published, streak.
//   alert      — errors and destructive actions.
//
// Depth is expressed by changing the ground, never by shadow — there is no shadow
// token any more. Focus and selection use Border.swift widths instead.

import SwiftUI

extension Color {
    // MARK: - 紙 — carries every "region" signal

    /// App background. The default ground for all content.
    static let tujiPaper = Color(hex: 0xFBF7EF)
    /// Secondary region: pressed state, input field, skeleton, unselected chip, image container.
    static let tujiPaper2 = Color(hex: 0xF2ECE0)
    /// Tertiary: disabled ground, lowest heatmap step, progress track.
    static let tujiPaper3 = Color(hex: 0xE5DCCB)

    // MARK: - 墨 — text and the only depth layer

    /// Primary text **and** dark-block ground. One role, not two — the old
    /// `tujiInk` / `tujiBgInk` pair held the same value under two names.
    static let tujiInk = Color(hex: 0x191512)
    /// Secondary text; tappable text that is not selected.
    static let tujiInk2 = Color(hex: 0x4A4239)
    /// Tertiary text, captions, placeholders, disabled text.
    static let tujiInk3 = Color(hex: 0x8A8073)
    /// The only line. 1px, for list separators and the scrolled nav bar underline.
    /// Replaces the old `tujiInk4`, whose only job was to be a translucent hairline.
    static let tujiRule = Color(hex: 0xD9D0C0)

    // MARK: - 瞳 — the only chromatic signal. Means 現在, nothing else.

    /// Primary button ground, selected tab indicator, progress fill, check mark,
    /// focus ring, search hit.
    static let tujiEye = Color(hex: 0xF5C84B)
    /// Pressed state for eye-coloured elements; text under 16pt on an eye ground.
    static let tujiEyeDeep = Color(hex: 0xC79A1E)

    // MARK: - 積累 — the brand teal's one job

    /// Brand colour, value fixed. Means only 你的積累 — never a button, nav, link
    /// or heading. A screen with no teal means the user has accumulated nothing
    /// here yet, which is the correct thing to show.
    static let tujiTeal = Color(hex: 0x006F72)
    /// Top two mastery steps; small text on a teal ground.
    static let tujiTealDeep = Color(hex: 0x004A4C)
    /// Low mastery ground, and the accumulation signal **on ink surfaces** — the deep
    /// teal only reaches 3.04:1 against `tujiInk`, this reaches 13.58:1.
    static let tujiTealSoft = Color(hex: 0xCFE3E0)

    // MARK: - 警示

    /// Errors, deletion, destructive actions, review rejection.
    static let tujiAlert = Color(hex: 0xD8452B)

    // MARK: - 遮罩

    /// Behind sheets and dialogs.
    static let tujiScrim = Color(hex: 0x191512).opacity(0.4)

    init(hex: UInt32, alpha: Double = 1.0) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: alpha
        )
    }
}

/// ShapeStyle-side aliases so `.background(.tujiPaper)`, `.foregroundStyle(.tujiInk)`
/// etc. work via leading-dot inference (mirrors how SwiftUI exposes `.red`,
/// `.blue` for built-in colors).
extension ShapeStyle where Self == Color {
    static var tujiPaper: Color {
        .tujiPaper
    }

    static var tujiPaper2: Color {
        .tujiPaper2
    }

    static var tujiPaper3: Color {
        .tujiPaper3
    }

    static var tujiInk: Color {
        .tujiInk
    }

    static var tujiInk2: Color {
        .tujiInk2
    }

    static var tujiInk3: Color {
        .tujiInk3
    }

    static var tujiRule: Color {
        .tujiRule
    }

    static var tujiEye: Color {
        .tujiEye
    }

    static var tujiEyeDeep: Color {
        .tujiEyeDeep
    }

    static var tujiTeal: Color {
        .tujiTeal
    }

    static var tujiTealDeep: Color {
        .tujiTealDeep
    }

    static var tujiTealSoft: Color {
        .tujiTealSoft
    }

    static var tujiAlert: Color {
        .tujiAlert
    }

    static var tujiScrim: Color {
        .tujiScrim
    }
}
