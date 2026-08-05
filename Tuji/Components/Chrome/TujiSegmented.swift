// Segmented control — replaces `.pickerStyle(.segmented)`.
//
// The system control's strongest fingerprint is not its corner radius, it is the
// *equal division* and the sliding thumb: three options always split the full
// width evenly, and that rhythm is recognisable in any app on the platform.
//
// So: left-aligned to the page margin, widths set by the text, and selection
// shown by inverting to an ink block instead of sliding a thumb. The inversion
// costs no new vocabulary — it is the same gesture chips, multi-select rows,
// sheet options and the tab bar already use, so it is learned once.

import SwiftUI

struct TujiSegmented<Value: Hashable>: View {
    let options: [(value: Value, title: LocalizedStringKey)]
    @Binding var selection: Value

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Space.s2) {
                ForEach(self.options, id: \.value) { option in
                    Button {
                        withAnimation(Motion.ease(Motion.d1)) {
                            self.selection = option.value
                        }
                    } label: {
                        Text(option.title)
                            .font(.tujiH3)
                            .padding(.horizontal, Space.s3)
                            .frame(height: 40)
                    }
                    .buttonStyle(SegmentStyle(selected: self.selection == option.value))
                    .accessibilityAddTraits(self.selection == option.value ? [.isSelected] : [])
                }
            }
            .padding(.horizontal, Space.s4)
        }
        .scrollClipDisabled()
    }
}

private struct SegmentStyle: ButtonStyle {
    let selected: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(self.selected ? Color.tujiPaper : .tujiInk2)
            .background(self.ground(pressed: configuration.isPressed))
    }

    private func ground(pressed: Bool) -> Color {
        if self.selected { return .tujiInk }
        return pressed ? .tujiPaper2 : .clear
    }
}

#Preview {
    struct Demo: View {
        @State private var pick = 0
        var body: some View {
            VStack(alignment: .leading, spacing: Space.s5) {
                TujiSegmented(
                    options: [(0, "圖鑑卡片"), (1, "合集")],
                    selection: self.$pick
                )
                TujiSegmented(
                    options: [(0, "探索"), (1, "已收藏")],
                    selection: self.$pick
                )
            }
            .padding(.vertical, Space.s5)
            .background(.tujiPaper)
        }
    }
    return Demo()
}
