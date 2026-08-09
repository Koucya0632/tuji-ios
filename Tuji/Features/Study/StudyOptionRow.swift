// One MCQ option row, shared by the 選字 (new-flow IdentifyView) and 複習
// (ReviewFlowView) surfaces — the two used to carry near-identical copies of
// this row plus a private OptStyle / OptionStyle struct. Pure presentation: it
// renders a letter + label and reports taps; the caller owns the answer state
// and resolves it via StudyOptionState.forOption(...).
//
// The old row was a pale-teal card with a circular letter chip, a 1.5pt border
// and a ✓/✗ SF Symbol on reveal. Every one of those is the platform's own
// vocabulary. What replaces them is the mark the rest of the app already uses:
// a correct answer becomes an ink block, and that inversion is unmistakable
// without a single icon, colour cue, or bounce.

import SwiftUI

struct StudyOptionRow: View {
    let letter: String
    let label: String
    let state: StudyOptionState
    let disabled: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: self.onTap) {
            HStack(spacing: Space.s3) {
                // A square, not a circle: the circle was the last round corner
                // left in the flow, and it read as a radio button.
                Text(self.letter)
                    .font(.tujiLabel)
                    .tracking(0.5)
                    .foregroundStyle(self.state.letterForeground)
                    .frame(width: 32, height: 32)
                    .background(self.state.letterGround)
                Text(self.label)
                    .font(.tujiH3)
                    .foregroundStyle(self.state.foreground)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, Space.s3)
            .frame(minHeight: 64)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(alignment: .leading) {
                HStack(spacing: 0) {
                    // A wrong pick keeps its ground and takes a 3pt alert edge.
                    // Flooding the row red makes a mistake look like a failure;
                    // it is one step in a review, and the correct answer lighting
                    // up as an ink block beside it is what carries the message.
                    if let edge = self.state.leadingEdge {
                        Rectangle().fill(edge).frame(width: Border.bw3)
                    }
                    Rectangle().fill(self.state.ground)
                }
            }
        }
        .buttonStyle(StudyOptionPress(state: self.state))
        .disabled(self.disabled)
        .opacity(self.state.opacity)
        .accessibilityValue(self.state.accessibilityValue.map { Text($0) } ?? Text(verbatim: ""))
    }
}

private struct StudyOptionPress: ButtonStyle {
    let state: StudyOptionState

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(configuration.isPressed && self.state == .idle ? Color.tujiPaper3 : .clear)
            .animation(Motion.ease(Motion.d1), value: configuration.isPressed)
    }
}

/// What one option is once the answer is out. Before the reveal every option is
/// `.idle`; the caller never builds these itself.
enum StudyOptionState: Equatable {
    case idle
    /// Picked, and right.
    case right
    /// Picked, and wrong.
    case wrong
    /// The answer, when something else was picked. Looks identical to `.right` —
    /// the two are separate only so VoiceOver can tell them apart.
    case answer
    /// Neither picked nor the answer, once the answer is out.
    case dim

    /// The reveal decision both MCQ surfaces used to duplicate.
    static func forOption(
        label: String,
        answer: String,
        picked: String?,
        revealed: Bool
    )
        -> StudyOptionState
    {
        guard revealed, let picked else { return .idle }
        let isAnswer = label == answer
        let isPicked = label == picked
        if isPicked, isAnswer { return .right }
        if isPicked, !isAnswer { return .wrong }
        if isAnswer { return .answer }
        return .dim
    }

    var ground: Color {
        switch self {
        case .right, .answer: .tujiInk
        case .idle, .wrong, .dim: .tujiPaper2
        }
    }

    var foreground: Color {
        switch self {
        case .right, .answer: .tujiPaper
        case .idle, .wrong: .tujiInk
        case .dim: .tujiInk2
        }
    }

    var letterGround: Color {
        switch self {
        case .right, .answer: .tujiCurrent
        case .idle, .wrong, .dim: .tujiPaper3
        }
    }

    var letterForeground: Color {
        switch self {
        case .idle, .wrong, .dim: .tujiInk2
        case .right, .answer: .tujiInk
        }
    }

    var leadingEdge: Color? {
        self == .wrong ? .tujiAlert : nil
    }

    /// The three unrelated options recede rather than disappear — they are still
    /// the alternatives that were on offer, and the user may want to reread them.
    var opacity: Double {
        self == .dim ? 0.4 : 1
    }

    /// Ink inversion and a 3pt edge are shape differences, not colour-only ones,
    /// so the visual language survives colour blindness. This covers VoiceOver.
    var accessibilityValue: LocalizedStringKey? {
        switch self {
        case .right: "答對了"
        case .wrong: "答錯了"
        case .answer: "正確答案"
        case .idle, .dim: nil
        }
    }
}
