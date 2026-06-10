// Pop Cards signature button — solid 4px drop (not blur), press flattens it.

import SwiftUI

struct BBtn: View {
    let title: String
    var bg: Color = .tujiYellow
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
                    .font(.system(size: 16, weight: .heavy))
            }
            .foregroundStyle(fg)
            .frame(maxWidth: fullWidth ? .infinity : nil)
            .padding(.vertical, Space.s4)
            .padding(.horizontal, Space.s6)
            .background {
                ZStack(alignment: .bottom) {
                    RoundedRectangle(cornerRadius: Radius.lg)
                        .fill(bg.darker())
                        .offset(y: pressed ? 0 : 4)
                    RoundedRectangle(cornerRadius: Radius.lg)
                        .fill(bg)
                        .offset(y: pressed ? 4 : 0)
                }
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
                withAnimation(.spring(duration: 0.12)) { pressed = new }
            }
    }
}

#Preview {
    VStack(spacing: Space.s4) {
        BBtn(title: "認識了", action: {})
        BBtn(title: "繼續", bg: .tujiTeal, fg: .white, fullWidth: true, action: {})
        BBtn(title: "完成", bg: .tujiTeal, fg: .white, icon: "checkmark", action: {})
        BBtn(title: "Disabled", action: {}).disabled(true)
    }
    .padding()
    .background(.tujiBg)
}
