// Color tokens — direction B (Pop Cards).
// Hex literals only allowed in this file (see .swiftlint.yml no_hex_color_outside_theme).

import SwiftUI

extension Color {
    static let tujiBg = Color(hex: 0xFFFCF5)
    static let tujiBgInk = Color(hex: 0x0F1A1A)
    static let tujiCard = Color.white
    static let tujiInk = Color(hex: 0x0F1A1A)
    static let tujiInk2 = Color(hex: 0x3F4F4F)
    static let tujiInk3 = Color(hex: 0x7C8C8C)
    static let tujiInk4 = Color(hex: 0xB5C2C2)
    static let tujiTeal = Color(hex: 0x006F72)
    static let tujiTealDark = Color(hex: 0x004A4C)
    static let tujiTealSoft = Color(hex: 0xD4ECEC)
    static let tujiYellow = Color(hex: 0xFFD24A)
    /// Streak / momentum accent. Split from coral so the flame (a positive
    /// achievement) never wears the same colour as errors and delete actions.
    static let tujiAmber = Color(hex: 0xF28C28)
    static let tujiCoral = Color(hex: 0xFF6F4D)
    static let tujiPink = Color(hex: 0xFFCDD2)
    static let tujiGreen = Color(hex: 0x4FAE6F)
    static let tujiPurple = Color(hex: 0x8B5CF6)

    init(hex: UInt32, alpha: Double = 1.0) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: alpha
        )
    }

    /// Approximate "darken by N%" via HSB brightness reduction.
    /// Used by BBtn's 4px drop shadow effect.
    func darker(by amount: Double = 0.16) -> Color {
        #if canImport(UIKit)
        let ui = UIColor(self)
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        ui.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        return Color(UIColor(hue: h, saturation: s, brightness: max(0, b - amount), alpha: a))
        #else
        return self
        #endif
    }
}

/// ShapeStyle-side aliases so `.background(.tujiBg)`, `.foregroundStyle(.tujiTeal)`
/// etc. work via leading-dot inference (mirrors how SwiftUI exposes `.red`,
/// `.blue` for built-in colors).
extension ShapeStyle where Self == Color {
    static var tujiBg: Color {
        .tujiBg
    }

    static var tujiBgInk: Color {
        .tujiBgInk
    }

    static var tujiCard: Color {
        .tujiCard
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

    static var tujiInk4: Color {
        .tujiInk4
    }

    static var tujiTeal: Color {
        .tujiTeal
    }

    static var tujiTealDark: Color {
        .tujiTealDark
    }

    static var tujiTealSoft: Color {
        .tujiTealSoft
    }

    static var tujiYellow: Color {
        .tujiYellow
    }

    static var tujiAmber: Color {
        .tujiAmber
    }

    static var tujiCoral: Color {
        .tujiCoral
    }

    static var tujiPink: Color {
        .tujiPink
    }

    static var tujiGreen: Color {
        .tujiGreen
    }

    static var tujiPurple: Color {
        .tujiPurple
    }
}
