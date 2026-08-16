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
    ///
    /// `height` only needs passing when the content genuinely does not fit the
    /// default — five options plus a footer, say. Leave it alone otherwise: the
    /// point of one number is that these sheets look like each other.
    func tujiSheet(
        isPresented: Binding<Bool>,
        title: LocalizedStringKey,
        height: CGFloat = TujiSheetShell<EmptyView>.defaultHeight,
        @ViewBuilder content: @escaping () -> some View
    )
        -> some View
    {
        self.sheet(isPresented: isPresented) {
            TujiSheetShell(title: title, height: height, content: content)
        }
    }
}

struct TujiSheetShell<Content: View>: View {
    /// 340, not a fraction of the screen: a settings picker with four rows
    /// should not occupy half a phone. This was a computed property whose body
    /// was the same literal, and whose doc claimed the sheet sized to its
    /// content — it never did. `.large` is still offered, so a caller with more
    /// rows than fit can be dragged up.
    static var defaultHeight: CGFloat {
        340
    }

    let title: LocalizedStringKey
    var height: CGFloat = TujiSheetShell<EmptyView>.defaultHeight
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: 0) {
            TujiSheetHeader(title: Text(self.title))
            self.content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.tujiPaper)
        .presentationDetents([.height(self.height), .large])
        .tujiSheetPresentation()
    }
}

/// The full-height variant, for sheets that are a *task* rather than a choice:
/// a form to fill in, a photo to correct, a catalogue to pick from.
///
/// These five screens each wrapped themselves in a `NavigationStack` purely to
/// borrow its bar — a whole navigation container, holding one title and one close
/// button, for a modal that never pushes anything. The stack is gone; the header
/// is the one above, so a form sheet and a picker sheet open with the same mark.
///
/// `closeDisabled` drives the drag-to-dismiss too. A close button that refuses
/// while the sheet still slides away on a swipe isn't protecting anything.
struct TujiFormSheet<Content: View>: View {
    let title: Text
    var closeDisabled: Bool = false
    /// Overrides plain dismissal — for a sheet that must ask before discarding.
    var onClose: (() -> Void)?
    @ViewBuilder var content: Content

    init(
        title: LocalizedStringKey,
        closeDisabled: Bool = false,
        onClose: (() -> Void)? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.title = Text(title)
        self.closeDisabled = closeDisabled
        self.onClose = onClose
        self.content = content()
    }

    var body: some View {
        VStack(spacing: 0) {
            TujiSheetHeader(
                title: self.title,
                closeDisabled: self.closeDisabled,
                onClose: self.onClose
            )
            self.content
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(.tujiPaper)
        .presentationDetents([.large])
        .tujiSheetPresentation()
        // A sheet that overrides close has something to ask before it goes, so
        // the drag gesture must not be a way around the question — that was the
        // 拍照新增 discard confirmation's one hole.
        .interactiveDismissDisabled(self.closeDisabled || self.onClose != nil)
    }
}

private struct TujiSheetHeader: View {
    let title: Text
    var closeDisabled: Bool = false
    var onClose: (() -> Void)?

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(.tujiInk)
                .frame(height: Border.bw3)

            HStack {
                self.title
                    .font(.tujiH2)
                    .foregroundStyle(.tujiInk)
                    .lineLimit(1)
                Spacer(minLength: Space.s2)
                // No centred title, no "完成" text button, no "取消" on the left —
                // those three together are the system sheet's toolbar.
                Button {
                    if let onClose = self.onClose { onClose() } else { self.dismiss() }
                } label: {
                    Image(systemName: "xmark")
                        .font(.tujiIcon(18, weight: .semibold))
                        .foregroundStyle(self.closeDisabled ? .tujiInk3 : .tujiInk2)
                        .frame(width: 48, height: 48)
                        .contentShape(.rect)
                }
                .disabled(self.closeDisabled)
                .accessibilityLabel(Text("關閉"))
                .padding(.trailing, -Space.s3)
            }
            .padding(.horizontal, Space.s4)
            .padding(.top, Space.s3)
        }
    }
}

private extension View {
    func tujiSheetPresentation() -> some View {
        self
            .presentationDragIndicator(.hidden)
            // Square corners. This is the whole point — the system's rounded sheet
            // is the single most recognisable modal shape on the platform.
            .presentationCornerRadius(Radius.r0)
            .presentationBackground(.tujiPaper)
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
