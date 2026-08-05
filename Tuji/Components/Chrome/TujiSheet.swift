// Bottom sheet — replaces the system sheet's appearance.
//
// The system sheet's fingerprint is a big corner radius, a grabber capsule, and
// the screen behind it shrinking into a rounded card. All three go. What is left
// reads as a sheet of paper pushed in from below, and the 3pt ink edge along its
// top is the same mark the tab bar, the selected state and the section indicator
// already use — nothing new to learn.
//
// `TujiOptionSheet` is the reason this exists. The four single-select settings
// pickers used to be pushed screens: tap a row, a whole screen slides in, tap an
// option, the screen slides back. That is three moves for one decision. As a
// sheet it is one, and the selected option uses the same ink inversion as
// everything else that means "this is the one".

import SwiftUI

extension View {
    /// Presents `content` as a square-cornered bottom sheet.
    func tujiSheet(
        isPresented: Binding<Bool>,
        title: LocalizedStringKey,
        @ViewBuilder content: @escaping () -> some View
    )
        -> some View
    {
        self.sheet(isPresented: isPresented) {
            TujiSheetShell(title: title, content: content)
        }
    }
}

struct TujiSheetShell<Content: View>: View {
    let title: LocalizedStringKey
    @ViewBuilder var content: Content
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(.tujiInk)
                .frame(height: Border.bw3)

            HStack {
                Text(self.title)
                    .font(.tujiH2)
                    .foregroundStyle(.tujiInk)
                Spacer()
                // No centred title, no "完成" text button, no "取消" on the left —
                // those three together are the system sheet's toolbar.
                Button { self.dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.tujiInk2)
                        .frame(width: 48, height: 48)
                        .contentShape(.rect)
                }
                .accessibilityLabel(Text("關閉"))
                .padding(.trailing, -Space.s3)
            }
            .padding(.horizontal, Space.s4)
            .padding(.top, Space.s3)

            self.content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.tujiPaper)
        .presentationDetents([.height(self.estimatedHeight), .large])
        .presentationDragIndicator(.hidden)
        // Square corners. This is the whole point — the system's rounded sheet is
        // the single most recognisable modal shape on the platform.
        .presentationCornerRadius(Radius.r0)
        .presentationBackground(.tujiPaper)
    }

    /// Sheets size to their content rather than to a fixed fraction; a settings
    /// picker with four rows should not occupy half the screen.
    private var estimatedHeight: CGFloat {
        340
    }
}

/// A single-select list inside a sheet. Picking closes it immediately — there is
/// nothing to confirm, because the change already applied.
struct TujiOptionSheet<Value: Hashable>: View {
    struct Option: Identifiable {
        let value: Value
        let title: Text
        var subtitle: Text?
        var id: Value {
            self.value
        }

        init(_ value: Value, title: LocalizedStringKey, subtitle: LocalizedStringKey? = nil) {
            self.value = value
            self.title = Text(title)
            self.subtitle = subtitle.map { (key: LocalizedStringKey) in Text(key) }
        }

        /// For labels already resolved by `tujiLocalized()` or coming from data.
        init(_ value: Value, verbatim title: String, verbatimSubtitle subtitle: String? = nil) {
            self.value = value
            self.title = Text(verbatim: title)
            self.subtitle = subtitle.map { Text(verbatim: $0) }
        }
    }

    let options: [Option]
    let selection: Value
    var footer: LocalizedStringKey?
    let onSelect: (Value) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                ForEach(Array(self.options.enumerated()), id: \.element.id) { index, option in
                    if index > 0 {
                        Rectangle()
                            .fill(.tujiRule)
                            .frame(height: Border.bw1)
                            .padding(.horizontal, Space.s4)
                    }
                    Button {
                        self.onSelect(option.value)
                        self.dismiss()
                    } label: {
                        TujiRow(
                            leading: { OptionLabel(option: option, selected: option.value == self.selection) },
                            trailing: { TujiSelectionMark(selected: option.value == self.selection) }
                        )
                    }
                    .tujiRowStyle()
                    .accessibilityAddTraits(option.value == self.selection ? [.isSelected] : [])
                }

                if let footer = self.footer {
                    Text(footer)
                        .font(.tujiBodySm)
                        .foregroundStyle(.tujiInk3)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, Space.s4)
                        .padding(.top, Space.s4)
                }
            }
            .padding(.top, Space.s3)
            .padding(.bottom, Space.s5)
        }
    }
}

private struct OptionLabel<Value: Hashable>: View {
    let option: TujiOptionSheet<Value>.Option
    let selected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            self.option.title
                .font(.tujiH3)
                .foregroundStyle(.tujiInk)
            if let subtitle = self.option.subtitle {
                subtitle
                    .font(.tujiBodySm)
                    .foregroundStyle(.tujiInk3)
            }
        }
        .padding(.vertical, Space.s2)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
