// Card shadow modifier — light, cool, no offset glare.

import SwiftUI

struct TujiCardShadow: ViewModifier {
    func body(content: Content) -> some View {
        content.shadow(color: .black.opacity(0.08), radius: 24, x: 0, y: 8)
    }
}

extension View {
    func tujiCardShadow() -> some View {
        modifier(TujiCardShadow())
    }
}
