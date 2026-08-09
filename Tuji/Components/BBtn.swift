// The app's primary button.
//
// The 4pt solid drop it used to carry is gone. That drop was a fake third
// dimension, and the system now has no shadow of any kind — but more than that,
// the personality it carried has been promoted from one component's decoration
// into a global rule: **press = change of ground, nothing moves.** Every tappable
// surface in the app now says it the same way.
//
// Haptics are unchanged. Removing the visual displacement would leave the button
// feeling dead without them.

import SwiftUI

struct BBtn: View {
    /// Held as `Text`, not `LocalizedStringKey`, for the reason `TujiRowLabel`
    /// documents: a caller with an already-resolved String had no way in, so it
    /// wrote `BBtn(title: "\(submitTitle)")` — which asks the catalogue for the
    /// key `%@`. That key is in `Localizable.xcstrings` with zero localizations,
    /// so those buttons render correctly *only until someone translates it*.
    let title: Text
    var bg: Color = .tujiBrandPrimary
    var fg: Color = .tujiInk
    var fullWidth: Bool = false
    var icon: String?
    let action: () -> Void

    init(
        title: LocalizedStringKey,
        bg: Color = .tujiBrandPrimary,
        fg: Color = .tujiInk,
        fullWidth: Bool = false,
        icon: String? = nil,
        action: @escaping () -> Void
    ) {
        self.init(text: Text(title), bg: bg, fg: fg, fullWidth: fullWidth, icon: icon, action: action)
    }

    /// For a title already resolved by `tujiLocalized()`, or built from data.
    init(
        localized title: String,
        bg: Color = .tujiBrandPrimary,
        fg: Color = .tujiInk,
        fullWidth: Bool = false,
        icon: String? = nil,
        action: @escaping () -> Void
    ) {
        self.init(
            text: Text(verbatim: title), bg: bg, fg: fg,
            fullWidth: fullWidth, icon: icon, action: action
        )
    }

    private init(
        text: Text,
        bg: Color,
        fg: Color,
        fullWidth: Bool,
        icon: String?,
        action: @escaping () -> Void
    ) {
        self.title = text
        self.bg = bg
        self.fg = fg
        self.fullWidth = fullWidth
        self.icon = icon
        self.action = action
    }

    @State private var pressed = false
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button(action: triggered) {
            HStack(spacing: Space.s2) {
                if let icon { Image(systemName: icon) }
                self.title
                    .font(.tujiH3)
            }
            .foregroundStyle(fg)
            .frame(maxWidth: fullWidth ? .infinity : nil)
            .padding(.vertical, Space.s3)
            .padding(.horizontal, Space.s4)
            .background {
                Rectangle()
                    .fill(bg)
                    // An ink wash works against any caller-supplied `bg`. The
                    // four fixed levels of the spec (primary/secondary/text/
                    // destructive) need BBtn to become a style enum, which is
                    // the chrome pass — not this one.
                    .overlay(Color.tujiInk.opacity(pressed ? 0.12 : 0))
            }
            .opacity(isEnabled ? 1 : 0.5)
        }
        .buttonStyle(PressTracker(pressed: $pressed))
    }

    private func triggered() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        action()
    }
}

private struct PressTracker: ButtonStyle {
    @Binding var pressed: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .onChange(of: configuration.isPressed) { _, new in
                withAnimation(Motion.ease(Motion.d1)) { pressed = new }
            }
    }
}

#Preview {
    VStack(spacing: Space.s3) {
        BBtn(title: "認識了", action: {})
        BBtn(title: "繼續", bg: .tujiBrandPrimary, fg: .tujiInk, fullWidth: true, action: {})
        BBtn(title: "完成", bg: .tujiBrandPrimary, fg: .tujiInk, icon: "checkmark", action: {})
        BBtn(title: "Disabled", action: {}).disabled(true)
    }
    .padding()
    .background(.tujiPaper)
}
