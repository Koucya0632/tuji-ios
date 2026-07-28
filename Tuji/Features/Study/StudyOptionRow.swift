// One MCQ option row, shared by the 選字 (new-flow IdentifyView) and 複習
// (ReviewFlowView) surfaces — the two used to carry near-identical copies of
// this row plus a private OptStyle / OptionStyle struct. Pure presentation: it
// renders a letter + label and reports taps; the caller owns the answer state
// and resolves the style via StudyOptionStyle.forOption(...).

import SwiftUI

struct StudyOptionRow: View {
    let letter: String
    let label: String
    let style: StudyOptionStyle
    let disabled: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: self.onTap) {
            HStack(spacing: Space.s3) {
                Text(self.letter)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(self.style.letterFg)
                    .frame(width: 24, height: 24)
                    .background(self.style.letterBg, in: .circle)
                Text(self.label)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(self.style.fg)
                Spacer()
                if let icon = self.style.icon {
                    Image(systemName: icon).foregroundStyle(self.style.iconColor)
                }
            }
            .padding(.horizontal, Space.s4)
            .padding(.vertical, Space.s3)
            .background(self.style.bg, in: .rect(cornerRadius: Radius.lg))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.lg)
                    .stroke(self.style.border, lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
        .disabled(self.disabled)
        .opacity(self.style.opacity)
    }
}

struct StudyOptionStyle {
    let bg: Color
    let border: Color
    let fg: Color
    let letterFg: Color
    let letterBg: Color
    let icon: String?
    let iconColor: Color
    let opacity: Double

    static let idle = StudyOptionStyle(
        bg: .tujiCard, border: .tujiInk4.opacity(0.25),
        fg: .tujiInk, letterFg: .tujiInk3, letterBg: .tujiTealSoft,
        icon: nil, iconColor: .clear, opacity: 1
    )
    static let right = StudyOptionStyle(
        bg: .tujiGreen.opacity(0.12), border: .tujiGreen,
        fg: .tujiInk, letterFg: .white, letterBg: .tujiGreen,
        icon: "checkmark.circle.fill", iconColor: .tujiGreen, opacity: 1
    )
    static let wrong = StudyOptionStyle(
        bg: .tujiCoral.opacity(0.12), border: .tujiCoral,
        fg: .tujiInk, letterFg: .white, letterBg: .tujiCoral,
        icon: "xmark.circle.fill", iconColor: .tujiCoral, opacity: 1
    )
    static let answer = StudyOptionStyle(
        bg: .tujiGreen.opacity(0.08), border: .tujiGreen.opacity(0.7),
        fg: .tujiInk, letterFg: .white, letterBg: .tujiGreen,
        icon: "arrow.left.circle.fill", iconColor: .tujiGreen, opacity: 1
    )
    static let dim = StudyOptionStyle(
        bg: .tujiCard, border: .tujiInk4.opacity(0.15),
        fg: .tujiInk3, letterFg: .tujiInk4, letterBg: .tujiInk4.opacity(0.15),
        icon: nil, iconColor: .clear, opacity: 0.5
    )

    /// The style for one option once the answer is revealed — the right / wrong /
    /// answer / dim decision both MCQ surfaces used to duplicate. Before reveal
    /// (or with nothing picked) every option is `.idle`.
    static func forOption(label: String, answer: String, picked: String?, revealed: Bool) -> StudyOptionStyle {
        guard revealed, let picked else { return .idle }
        let isAnswer = label == answer
        let isPicked = label == picked
        if isPicked, isAnswer { return .right }
        if isPicked, !isAnswer { return .wrong }
        if isAnswer { return .answer }
        return .dim
    }
}
