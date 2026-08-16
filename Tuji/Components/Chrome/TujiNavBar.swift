// The navigation bar — replaces the system bar's appearance, not its behaviour.
//
// The system bar has three fingerprints: a centred title, a `‹ 返回` back button
// carrying the previous screen's name, and a blurred ground with a hairline once
// you scroll. All three go.
//
// What stays is everything about *moving*: push and pop, the back-swipe gesture,
// system transitions, Dynamic Type, VoiceOver, safe areas. `.navigationTitle` is
// still set by every screen — it is no longer drawn, but it is what VoiceOver
// announces, what the multitasking window is called, and what a pushed child's
// back button would say. Hiding a bar is not the same as having no bar.
//
// The 56pt of quiet at the top of every screen is the point, not an accident:
// with the title moved down into the content flow it can be set at 34pt, and
// that contrast is where the page gets its rhythm.

import SwiftUI

enum TujiNavLeading {
    /// `←` — pops the current screen.
    case back
    /// `✕` — dismisses a modal or leaves a study flow.
    case close
    /// Nothing on the left (tab roots).
    case none
}

struct TujiNavBar<Trailing: View>: View {
    var leading: TujiNavLeading = .back
    /// Shown only once the caller says the in-content title has scrolled away.
    var compactTitle: Text?
    var showsRule: Bool = false
    /// Replaces plain dismissal — for a screen that must ask before it goes
    /// (leaving a review mid-way) rather than just leaving.
    var onLeading: (() -> Void)?
    @ViewBuilder var trailing: Trailing

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        HStack(spacing: Space.s3) {
            self.leadingButton
            if let compactTitle {
                compactTitle
                    .font(.tujiH3)
                    .foregroundStyle(.tujiInk)
                    .lineLimit(1)
                    .transition(.opacity)
            }
            Spacer(minLength: 0)
            self.trailing
        }
        .padding(.horizontal, Space.s4)
        .frame(height: 56)
        .background(alignment: .bottom) {
            if self.showsRule {
                VStack(spacing: 0) {
                    Rectangle().fill(.tujiPaper)
                    Rectangle().fill(.tujiRule).frame(height: Border.bw1)
                }
            }
        }
        .animation(Motion.ease(Motion.d2), value: self.showsRule)
    }

    @ViewBuilder
    private var leadingButton: some View {
        switch self.leading {
        case .back:
            self.iconButton("arrow.left", label: "返回")
        case .close:
            self.iconButton("xmark", label: "關閉")
        case .none:
            EmptyView()
        }
    }

    private func iconButton(_ systemName: String, label: LocalizedStringKey) -> some View {
        Button {
            if let onLeading = self.onLeading { onLeading() } else { self.dismiss() }
        } label: {
            Image(systemName: systemName)
                .font(.tujiIcon(20, weight: .semibold))
                .foregroundStyle(.tujiInk)
                // Visual size is 24; the tap target is the 48 the whole system uses.
                .frame(width: 48, height: 48)
                .contentShape(.rect)
        }
        .accessibilityLabel(Text(label))
        // The leading icon sits on the page margin, not inset from it — every
        // screen's first element starts on the same vertical line.
        .padding(.leading, -Space.s3)
    }
}

extension TujiNavBar where Trailing == EmptyView {
    init(
        leading: TujiNavLeading = .back,
        compactTitle: Text? = nil,
        showsRule: Bool = false,
        onLeading: (() -> Void)? = nil
    ) {
        self.init(
            leading: leading,
            compactTitle: compactTitle,
            showsRule: showsRule,
            onLeading: onLeading,
            trailing: { EmptyView() }
        )
    }
}

// MARK: - Trailing actions

/// A 24pt icon action for the bar's trailing edge. At most two, or one text
/// action — never both, and never a row of four.
struct TujiNavIcon: View {
    let systemName: String
    let label: LocalizedStringKey
    let action: () -> Void

    var body: some View {
        Button(action: self.action) {
            Image(systemName: self.systemName)
                .font(.tujiIcon(19, weight: .semibold))
                .foregroundStyle(.tujiInk)
                .frame(width: 44, height: 48)
                .contentShape(.rect)
        }
        .accessibilityLabel(Text(self.label))
    }
}

/// A text action for the bar's trailing edge. Underlined, because with teal
/// demoted to "accumulation" the system has no colour that means "tappable".
struct TujiNavTextAction: View {
    let title: LocalizedStringKey
    /// Unavailable actions lose the underline as well as the ink: with teal gone
    /// as the tappable signal, a grey *underlined* word still reads as a link.
    var isEnabled: Bool = true
    let action: () -> Void

    var body: some View {
        Button(action: self.action) {
            Text(self.title)
                .font(.tujiLabel)
                .tracking(0.5)
                .foregroundStyle(self.isEnabled ? Color.tujiInk : .tujiInk3)
                .underline(self.isEnabled, pattern: .solid)
                .frame(height: 48)
                .contentShape(.rect)
        }
        .disabled(!self.isEnabled)
    }
}

// MARK: - Screen title

/// The screen's real title, living in the content flow rather than in the bar.
struct TujiScreenTitle: View {
    let text: Text

    init(_ key: LocalizedStringKey) {
        self.text = Text(key)
    }

    /// For titles already resolved by `tujiLocalized()` or coming from data.
    init(localized value: String) {
        self.text = Text(verbatim: value)
    }

    var body: some View {
        self.text
            .font(.tujiH1)
            .foregroundStyle(.tujiInk)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Space.s4)
            .padding(.top, Space.s2)
            .padding(.bottom, Space.s4)
            .accessibilityAddTraits(.isHeader)
    }
}

#Preview {
    VStack(spacing: 0) {
        TujiNavBar(leading: .back) {
            TujiNavIcon(systemName: "magnifyingglass", label: "搜尋") {}
            TujiNavIcon(systemName: "camera", label: "拍照") {}
        }
        TujiScreenTitle("圖鑑管理")
        TujiSection(title: "學習") {
            Button {} label: { TujiRow("學習語言", value: "英文") }.tujiRowStyle()
        }
        Spacer()
        TujiNavBar(leading: .close, compactTitle: Text("設定"), showsRule: true) {
            TujiNavTextAction(title: "選取") {}
        }
    }
    .background(.tujiPaper)
}
