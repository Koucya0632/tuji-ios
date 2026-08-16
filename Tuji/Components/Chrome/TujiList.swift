// The list — replaces SwiftUI's `List` / `Form`.
//
// iOS's inset-grouped list is recognisable because three things are true at once:
// it is rounded, it is a white card, and it floats on a tinted ground. Take all
// three away and there is no residue left to recognise.
//
// Full-bleed rows are what makes that work: with no card edge to align to, row
// content aligns straight to the 24pt page margin, and that single vertical line
// runs through every screen in the app. It is the skeleton that replaces the card.
//
// Sections are separated by 40pt of nothing. The header sits outside the rows,
// so the group reads as a heading over a list rather than as its first row.

import SwiftUI

// MARK: - Section

/// A titled group of rows. Draws hairlines *between* rows and never after the
/// last one — a trailing rule would read as the start of another group.
struct TujiSection<Content: View>: View {
    var title: LocalizedStringKey?
    var footer: LocalizedStringKey?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let title {
                Text(title)
                    .font(.tujiLabel)
                    .tracking(0.5)
                    .foregroundStyle(.tujiInk3)
                    .padding(.horizontal, Space.s4)
                    .padding(.bottom, Space.s2)
            }

            // `_VariadicView` is the only way to learn how many rows the caller
            // passed. A ViewBuilder cannot be counted, and every alternative
            // (arrays of AnyView, a separator baked into each row) either loses
            // type safety or draws the trailing rule this design forbids.
            _VariadicView.Tree(SeparatedRows()) {
                content
            }

            if let footer {
                Text(footer)
                    .font(.tujiBodySm)
                    .foregroundStyle(.tujiInk3)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, Space.s4)
                    .padding(.top, Space.s2)
            }
        }
        .padding(.top, Space.s5)
    }
}

private struct SeparatedRows: _VariadicView_UnaryViewRoot {
    func body(children: _VariadicView.Children) -> some View {
        VStack(spacing: 0) {
            ForEach(children) { child in
                if child.id != children.first?.id {
                    Rectangle()
                        .fill(.tujiRule)
                        .frame(height: Border.bw1)
                        .padding(.horizontal, Space.s4)
                }
                child
            }
        }
    }
}

// MARK: - Row

/// One row. Height follows what it carries: 56 plain, 72 with a subtitle,
/// 88 with a 56pt thumbnail.
struct TujiRow<Leading: View, Trailing: View>: View {
    @ViewBuilder var leading: Leading
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: Space.s3) {
            leading
            Spacer(minLength: Space.s2)
            trailing
        }
        .padding(.horizontal, Space.s4)
        .frame(minHeight: 56)
        .contentShape(.rect)
    }
}

extension TujiRow where Leading == TujiRowLabel, Trailing == TujiRowAccessory {
    /// The common case: a label, an optional explanation, an optional current
    /// value, and the forward arrow.
    init(
        _ label: LocalizedStringKey,
        subtitle: LocalizedStringKey? = nil,
        value: String? = nil,
        showsArrow: Bool = true,
        destructive: Bool = false
    ) {
        self.init(
            leading: { TujiRowLabel(label: label, subtitle: subtitle, destructive: destructive) },
            trailing: { TujiRowAccessory(value: value, showsArrow: showsArrow) }
        )
    }
}

/// Holds `Text`, not `String`, on purpose.
///
/// Both kinds of localised value reach these rows: catalog keys resolved by the
/// SwiftUI environment (`LocalizedStringKey`), and strings already resolved by
/// `tujiLocalized()` on the model side. Taking `LocalizedStringKey` alone would
/// force callers to wrap the second kind, which looks up an already-translated
/// string as if it were a key and silently misses. Taking `String` alone would
/// drop the first kind out of the interface-language switch entirely.
struct TujiRowLabel: View {
    let label: Text
    var subtitle: Text?
    var destructive: Bool = false

    init(label: LocalizedStringKey, subtitle: LocalizedStringKey? = nil, destructive: Bool = false) {
        self.label = Text(label)
        self.subtitle = subtitle.map { (key: LocalizedStringKey) in Text(key) }
        self.destructive = destructive
    }

    /// For values that `tujiLocalized()` has already resolved.
    init(localized label: String, localizedSubtitle subtitle: String? = nil, destructive: Bool = false) {
        self.label = Text(verbatim: label)
        self.subtitle = subtitle.map { Text(verbatim: $0) }
        self.destructive = destructive
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            self.label
                .font(.tujiH3)
                .foregroundStyle(self.destructive ? .tujiAlert : .tujiInk)
            if let subtitle = self.subtitle {
                subtitle
                    .font(.tujiBodySm)
                    .foregroundStyle(.tujiInk3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, Space.s2)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct TujiRowAccessory: View {
    var value: String?
    var showsArrow: Bool = true

    var body: some View {
        HStack(spacing: Space.s2) {
            if let value {
                Text(value)
                    .font(.tujiBody)
                    .foregroundStyle(.tujiInk2)
                    .lineLimit(1)
            }
            if self.showsArrow {
                // `→`, not `›`. The chevron is iOS's own accent; a horizontal
                // arrow implies moving forward and shares the 2pt round-cap
                // stroke every other icon in the app uses.
                Image(systemName: "arrow.right")
                    .font(.tujiIcon(16, weight: .semibold))
                    .foregroundStyle(.tujiInk3)
            }
        }
    }
}

// MARK: - Press behaviour

/// Press = the ground changes. Nothing moves, nothing fades.
/// Destructive rows invert instead — that press has weight.
struct TujiRowButtonStyle: ButtonStyle {
    var destructive: Bool = false
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(self.isEnabled ? Color.tujiInk : .tujiInk3)
            .background(self.ground(pressed: configuration.isPressed))
            .animation(Motion.ease(Motion.d1), value: configuration.isPressed)
    }

    private func ground(pressed: Bool) -> Color {
        guard pressed else { return .tujiPaper }
        return self.destructive ? .tujiAlert : .tujiPaper2
    }
}

extension View {
    /// Applies the row press behaviour. Use on `NavigationLink` and `Button`.
    func tujiRowStyle(destructive: Bool = false) -> some View {
        self.buttonStyle(TujiRowButtonStyle(destructive: destructive))
    }
}

#Preview {
    ScrollView {
        VStack(spacing: 0) {
            TujiSection(title: "學習") {
                Button {} label: {
                    TujiRow("學習語言", subtitle: "英文與日文的學習進度會分開保留", value: "英文")
                }
                .tujiRowStyle()
                Button {} label: {
                    TujiRow("每日目標題數", value: "10 題")
                }
                .tujiRowStyle()
            }
            TujiSection(title: "危險", footer: "清除學習進度會刪除掌握度與答題紀錄。") {
                Button {} label: {
                    TujiRow("清除學習進度", showsArrow: false, destructive: true)
                }
                .tujiRowStyle(destructive: true)
            }
        }
    }
    .background(.tujiPaper)
}

/// The "this is the one you picked" mark for selection rows and sheet options.
/// A 瞳黃 check, because being the current selection is exactly what 瞳黃 means.
struct TujiSelectionMark: View {
    let selected: Bool

    var body: some View {
        Image(systemName: "checkmark")
            .font(.tujiIcon(16, weight: .bold))
            .foregroundStyle(.tujiCurrent)
            .opacity(self.selected ? 1 : 0)
            .frame(width: 24)
            .accessibilityHidden(true)
    }
}

/// A small label whose 3pt leading edge carries the colour, so the word itself
/// stays neutral (C.9). A red-on-red 未通過 reads as an alarm; a rejection — or
/// having missed a word twice — is information, not an emergency.
struct TujiStatusEdgeLabel: View {
    let text: Text
    let edge: Color

    var body: some View {
        self.text
            .font(.tujiLabel)
            .tracking(0.5)
            .foregroundStyle(.tujiInk2)
            .lineLimit(1)
            .padding(.horizontal, Space.s2)
            .frame(height: 24)
            .background(alignment: .leading) {
                HStack(spacing: 0) {
                    Rectangle().fill(self.edge).frame(width: Border.bw3)
                    Rectangle().fill(.tujiPaper2)
                }
            }
    }
}

/// Review-state label (C.9).
struct TujiStatusLabel: View {
    let status: AtlasReviewStatus

    var body: some View {
        TujiStatusEdgeLabel(text: Text(verbatim: self.status.label), edge: self.edge)
            .accessibilityLabel(Text(verbatim: self.status.label))
    }

    /// 已公開 is accumulation, 審核中 is "happening now", 未通過/已下架 is the one
    /// state the user may need to act on.
    private var edge: Color {
        switch self.status {
        case .approved: .tujiAccumulation
        case .pending, .pendingAuto, .pendingReview: .tujiCurrent
        case .rejected, .takedown: .tujiAlert
        case .draft, .withdrawn: .tujiInk3
        }
    }
}
