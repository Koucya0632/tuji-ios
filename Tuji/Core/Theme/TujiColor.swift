// Color tokens — 紙與墨 (Paper & Ink).
// Hex literals only allowed in this file (see .swiftlint.yml no_hex_color_outside_theme).
//
// The system has exactly six meanings, and every colour belongs to one of them.
// A colour that cannot be written into one of these sentences does not enter the system:
//
//   紙 (paper) — the ground. Three steps, expressing region hierarchy.
//   墨 (ink)   — text, and "this one is selected / this one is primary".
//   品牌 (brand) — Tuji's identity. Yellow is primary; cocoa is the supporting ground.
//   現在 (current) — Where the next step is, where you are, what is running.
//   積累 (accumulation) — Mastery, completion, learned, published, streak.
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

    // MARK: - 品牌 — identity, independent from UI state

    /// Tuji's primary brand colour, taken from the mascot's eyes. Brand surfaces
    /// and the app's primary action share this value today, but use different
    /// semantic tokens so either can evolve without recolouring the other.
    static let tujiBrandPrimary = Color(hex: 0xF5C84B)
    static let tujiBrandPrimaryPressed = Color(hex: 0xC79A1E)
    /// Warm supporting brand ground, shared with the app icon background.
    static let tujiBrandSecondary = Color(hex: 0x59483D)

    // MARK: - 現在 — current focus and action

    /// Selected tab indicator, active progress, check mark, focus ring and search hit.
    static let tujiCurrent = tujiBrandPrimary
    /// Pressed state for current-coloured elements; text under 16pt on a current ground.
    static let tujiCurrentDeep = tujiBrandPrimaryPressed

    // MARK: - 積累 — learned value, not brand identity

    /// Means only 你的積累 — never a generic button, nav, link or heading. A screen
    /// with no accumulation colour means the user has accumulated nothing
    /// here yet, which is the correct thing to show.
    /// A slightly deeper form of the chosen mist blue keeps normal-size text
    /// above 4.5:1 on `tujiPaper` while retaining the same calm blue character.
    static let tujiAccumulation = Color(hex: 0x5A718A)
    /// High mastery ground; text on the soft accumulation ground.
    static let tujiAccumulationDeep = Color(hex: 0x40566D)
    /// Low mastery ground, and the accumulation signal on ink surfaces.
    static let tujiAccumulationSoft = Color(hex: 0xDDE5EC)

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

    static var tujiBrandPrimary: Color {
        .tujiBrandPrimary
    }

    static var tujiBrandPrimaryPressed: Color {
        .tujiBrandPrimaryPressed
    }

    static var tujiBrandSecondary: Color {
        .tujiBrandSecondary
    }

    static var tujiCurrent: Color {
        .tujiCurrent
    }

    static var tujiCurrentDeep: Color {
        .tujiCurrentDeep
    }

    static var tujiAccumulation: Color {
        .tujiAccumulation
    }

    static var tujiAccumulationDeep: Color {
        .tujiAccumulationDeep
    }

    static var tujiAccumulationSoft: Color {
        .tujiAccumulationSoft
    }

    static var tujiAlert: Color {
        .tujiAlert
    }

    static var tujiScrim: Color {
        .tujiScrim
    }
}
