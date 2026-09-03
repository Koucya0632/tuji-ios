// One MCQ option row, shared by the 選字 (new-flow IdentifyView) and 複習
// (ReviewFlowView) surfaces — the two used to carry near-identical copies of
// this row plus a private OptStyle / OptionStyle struct. Pure presentation: it
// renders a letter + label and reports taps; the caller owns the answer state
// and resolves it via StudyOptionState.forOption(...).
//
// The old row was a pale-teal card with a circular letter chip, a 1.5pt border
// and a ✓/✗ SF Symbol on reveal. Every one of those is the platform's own
// vocabulary. What replaces them is the mark the rest of the app already uses:
// the answer becomes an ink block, and that inversion is unmistakable without a
// single icon or bounce. The pick the user actually made is then named by a 3pt
// frame around it — 積累 when it landed, alert when it did not.

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
            .background { Rectangle().fill(self.state.ground) }
            // Two independent signals, deliberately: the **ground** says which
            // one is the answer (ink inversion), the **frame** says which one
            // the user tapped. A right pick carries both, a wrong pick only the
            // frame, and the answer nobody chose only the ground.
            //
            // Neither floods the row. A red fill makes a mistake look like a
            // failure — it is one step in a review — and a 3pt frame is enough
            // to find your own tap among four rows.
            //
            // A frame rather than the leading edge the wrong state used to have,
            // because 複習 now draws it **while the question is still open** —
            // with no answer lit beside it to say what the red means, a line
            // down one side is too quiet to read as "not this one". The left
            // side of the frame is the edge that was already there.
            .overlay {
                if let border = self.state.border {
                    Rectangle().strokeBorder(border, lineWidth: Border.bw3)
                }
            }
        }
        .buttonStyle(StudyOptionPress(state: self.state))
        .disabled(self.disabled)
        .opacity(self.state.opacity)
        // A wrong pick shakes once, the moment it happens.
        //
        // The frame is a *state*: it says "this one is out" for as long as the
        // question lasts, and a state that is simply there is easy to not
        // notice arriving — especially in 複習, where the picked row is the only
        // thing on screen that changed and the question otherwise carries on
        // exactly as before. The shake is the *event*.
        //
        // Keyed on entering `.wrong`, so the rows ruled out earlier hold still
        // when the answer finally lands — re-shaking them would report old
        // mistakes as if they had just been made.
        .keyframeAnimator(
            initialValue: CGFloat.zero,
            trigger: self.state == .wrong
        ) { row, dx in
            row.offset(x: dx)
        } keyframes: { _ in
            KeyframeTrack {
                LinearKeyframe(-Shake.amplitude, duration: Shake.out)
                LinearKeyframe(Shake.amplitude * 0.7, duration: Shake.back)
                LinearKeyframe(-Shake.amplitude * 0.25, duration: Shake.back)
                CubicKeyframe(0, duration: Shake.settle)
            }
        }
        .accessibilityValue(self.state.accessibilityValue.map { Text($0) } ?? Text(verbatim: ""))
    }
}

/// The wrong-pick nudge: one lateral shake out, back, and done.
///
/// It starts on the **first rendered frame after the tap** — measured off a
/// 60fps capture, the row is already displaced before the alert frame has
/// finished drawing. Nothing defers it; the state flip and the trigger happen
/// in the same turn as the tap.
///
/// **Keyframes, not phases, and that is the whole point.** A `phaseAnimator`
/// animates *to* a phase and then waits for the next one to be scheduled, so
/// the gap between phases lands exactly where the motion has stopped — at the
/// extreme. Measured off a 60fps capture, that version **snapped to −7.3pt in a
/// single frame and then held it for ~95ms**, and did the same at the far side:
/// a sideways jump that parks, followed by a shake, rather than one shake. The
/// keyframe track is a single timeline sampled every display frame — it sweeps
/// 0 → −7.3pt over 29ms and never stops moving, 195ms end to end.
///
/// **Linear for the throws, cubic only for the settle.** `CubicKeyframe` splines
/// *through* its values rather than landing on them, and with a neighbour
/// pulling the other way it rounds the corner off: an all-cubic version measured
/// a first throw of −3.3pt against a −7pt target, so the shake came out weak
/// first and strong second — the opposite of damped. Linear hits the number.
/// At 50–60ms a segment there is no perceptible difference in easing anyway;
/// the last one stays cubic because coming to rest is the one part slow enough
/// to see.
///
/// Deliberately not `Motion` tokens. That scale is the three durations the
/// whole app moves at, and this is one component's error feedback — a fourth
/// entry there would invite the next person to animate something else at
/// "shake speed". It does not overshoot its rest position: it starts and ends
/// at zero.
private enum Shake {
    /// How far the first throw goes. Everything after it is a fraction of this,
    /// so the shake damps by construction rather than by four hand-picked
    /// numbers that could drift apart.
    static let amplitude: CGFloat = 7

    static let out: Double = 0.05
    static let back: Double = 0.06
    static let settle: Double = 0.05
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
    ///
    /// `wrongPicks` is 複習's 看圖選字: options ruled out while the question is
    /// still open. They keep the mark **through** the reveal too — one of them
    /// is still the option the user got wrong, and letting it fall to `.dim`
    /// beside the answer would erase the only trace of the attempt. Empty for
    /// 學新字, whose first pick ends the question either way.
    static func forOption(
        label: String,
        answer: String,
        picked: String?,
        revealed: Bool,
        wrongPicks: Set<String> = []
    )
        -> StudyOptionState
    {
        if wrongPicks.contains(label) { return .wrong }
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

    /// Which row the user tapped, and how it went. `.answer` deliberately has
    /// none: it is the answer they did *not* pick, and the ink ground already
    /// says so — a frame there would claim a tap that never happened.
    ///
    /// 積累 for the right one rather than a new green: the palette has six
    /// meanings and none of them is green, and 聽句's two picture options were
    /// already drawing a correct answer in this exact colour.
    var border: Color? {
        switch self {
        case .right: .tujiAccumulation
        case .wrong: .tujiAlert
        case .idle, .answer, .dim: nil
        }
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
