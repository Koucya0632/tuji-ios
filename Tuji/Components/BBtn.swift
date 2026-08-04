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
    let title: LocalizedStringKey
    var bg: Color = .tujiEye
    var fg: Color = .tujiInk
    var fullWidth: Bool = false
    var icon: String?
    let action: () -> Void

    @State private var pressed = false
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button(action: triggered) {
            HStack(spacing: Space.s2) {
                if let icon { Image(systemName: icon) }
                Text(title)
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
        BBtn(title: "繼續", bg: .tujiEye, fg: .tujiInk, fullWidth: true, action: {})
        BBtn(title: "完成", bg: .tujiEye, fg: .tujiInk, icon: "checkmark", action: {})
        BBtn(title: "Disabled", action: {}).disabled(true)
    }
    .padding()
    .background(.tujiPaper)
}
