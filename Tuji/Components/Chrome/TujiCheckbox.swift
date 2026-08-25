// The on/off control — replaces `Toggle`'s capsule switch.
//
// The system switch is a capsule with a sliding knob, tinted with the app accent.
// All three of those are iOS's accent rather than ours, so the control becomes a
// square: ink ground when on, with the check drawn in 瞳黃 — the same colour that
// marks "this is the current one" on primary buttons and the selected tab.
//
// It is the only element allowed to scale on press. At 28pt a change of ground is
// too small to register, and the alternative (moving it) is the thing the rest of
// the system gave up.
//
// Visually a checkbox, semantically still an instant-effect switch — so it keeps
// `.isToggle`, and row titles stay declarative ("每日提醒") rather than
// imperative ("開啟每日提醒").

import SwiftUI

struct TujiCheckbox: View {
    @Binding var isOn: Bool
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button {
            withAnimation(Motion.ease(Motion.d1)) { self.isOn.toggle() }
        } label: {
            ZStack {
                Rectangle().fill(self.ground)
                if self.isOn {
                    Image(systemName: "checkmark")
                        .font(.tujiIcon(15, weight: .bold))
                        .foregroundStyle(self.isEnabled ? Color.tujiCurrent : .tujiInk3)
                }
            }
            .frame(width: 28, height: 28)
            .contentShape(.rect)
        }
        .buttonStyle(CheckboxPress())
        .frame(width: 48, height: 48)
        .accessibilityAddTraits(.isToggle)
        .accessibilityValue(Text(self.isOn ? "已開啟" : "已關閉"))
    }

    private var ground: Color {
        guard self.isEnabled else { return .tujiPaper3 }
        return self.isOn ? .tujiInk : .tujiPaper2
    }
}

private struct CheckboxPress: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .animation(Motion.ease(Motion.d1), value: configuration.isPressed)
    }
}

#Preview {
    struct Demo: View {
        @State private var a = true
        @State private var b = false
        var body: some View {
            VStack(spacing: 0) {
                TujiSection(title: "學習") {
                    TujiRow(
                        leading: { TujiRowLabel(label: "中文釋義") },
                        trailing: { TujiCheckbox(isOn: self.$a) }
                    )
                    TujiRow(
                        leading: { TujiRowLabel(label: "每日提醒", subtitle: "尚未開放") },
                        trailing: { TujiCheckbox(isOn: self.$b).disabled(true) }
                    )
                }
            }
            .background(.tujiPaper)
        }
    }
    return Demo()
}
