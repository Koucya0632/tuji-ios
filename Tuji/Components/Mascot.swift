// Tuji's official black-cat mascot. All six poses share the same public API
// on iOS and Web so product surfaces can choose an emotional state without
// knowing how the artwork is stored.

import SwiftUI

enum MascotPose: String, CaseIterable {
    case face, wave, think, cheer, sleep, peek
}

extension MascotPose {
    // Each pose is composed differently inside its 512² canvas (floating head,
    // full sitting body, wide curl, paws at the edge…). These fractions describe
    // where the *visible* artwork lives so callers can seat every pose on a
    // common baseline instead of hand-tuning per-pose offsets.

    /// Empty space above the artwork, as a fraction of the frame height.
    var topInset: CGFloat {
        switch self {
        case .face: 0.06
        case .wave: 0.05
        case .think: 0.05
        case .cheer: 0.06
        case .sleep: 0.28
        case .peek: 0.10
        }
    }

    /// Vertical position of the cat's visual "ground line" (lowest mass / feet)
    /// as a fraction of the frame height, measured from the top.
    var groundLine: CGFloat {
        switch self {
        case .face: 0.82
        case .wave: 0.96
        case .think: 0.95
        case .cheer: 0.95
        case .sleep: 0.86
        case .peek: 0.99
        }
    }

    /// Contact-shadow width relative to the frame, roughly matching how much
    /// surface the pose's body actually covers.
    var contactWidth: CGFloat {
        switch self {
        case .face: 0.40
        case .wave: 0.52
        case .think: 0.54
        case .cheer: 0.58
        case .sleep: 0.68
        case .peek: 0.58
        }
    }

    /// Visible artwork height as a fraction of the frame, after trimming the
    /// transparent margins above and below.
    var visibleHeightRatio: CGFloat {
        self.groundLine - self.topInset
    }
}

struct Mascot: View {
    let pose: MascotPose
    var size: CGFloat = 56

    var body: some View {
        Image("mascot-\(pose.rawValue)")
            .resizable()
            .aspectRatio(contentMode: .fit)
            .accessibilityHidden(true)
            .frame(width: size, height: size)
    }
}

/// The cat's eye, drawn rather than cropped: gold iris, ink pupil, one
/// catchlight up and to the right.
///
/// It is the mascot's eye and a camera lens at the same time, which is why it
/// can stand in for a shutter button. Both are the same three concentric
/// things — a coloured ring, a dark centre, a highlight where the light gets
/// in — and the app's primary brand colour is documented as taken from these
/// eyes (`TujiColor.tujiBrandPrimary`), so the mark is not borrowing the
/// palette, it is where the palette came from.
///
/// **This is the one round thing in the app, and that is deliberate.**
/// `Radius.r0` is 0 and every chip, button, card and sheet obeys it. The rule
/// governs UI chrome — shapes the interface invents. A mark is not chrome: it
/// has the form it has, the same carve-out `Font.tujiWordmark` gets for setting
/// the logotype outside the type scale. Rounding a *button* would break the
/// system; drawing the cat's eye as anything but a circle would break the cat.
///
/// Drawn from shapes rather than cropped out of `mascot-face`, because the
/// artwork is a 512² painting with soft shading — scaled down to 48pt its
/// gradients turn to mud, and it carries a highlight, fur edge and eyelid that
/// a 30pt mark cannot spare the pixels for.
struct MascotEye: View {
    var size: CGFloat = 48

    /// Measured off `mascot-face.png` (eye ⌀88px, pupil ⌀62, catchlight ⌀18):
    /// the pupil is about seven tenths of the eye, leaving a *thin* iris ring
    /// rather than the donut a heavier one reads as, and the catchlight sits
    /// high and outboard rather than centred.
    private var pupil: CGFloat {
        self.size * 0.70
    }

    private var catchlight: CGFloat {
        self.size * 0.20
    }

    var body: some View {
        ZStack {
            Circle().fill(.tujiBrandPrimary)
            Circle()
                .fill(.tujiInk)
                .frame(width: self.pupil, height: self.pupil)
            Circle()
                .fill(.tujiPaper)
                .frame(width: self.catchlight, height: self.catchlight)
                .offset(x: self.size * 0.12, y: -self.size * 0.14)
        }
        .frame(width: self.size, height: self.size)
        .accessibilityHidden(true)
    }
}

/// How a free-standing mascot is grounded into its surface.
enum MascotGrounding {
    /// Soft dark contact shadow — for light surfaces.
    case shadow
    /// Soft light halo — for dark surfaces where a shadow vanishes and the
    /// black cat would otherwise sink into the background.
    case glow
    case none
}

/// The standard in-app mascot treatment: the cat grounded by a soft contact
/// shadow (or halo) instead of a flat colored disc, so the art sits *in* the
/// surface rather than pasted on top.
///
/// The figure trims the transparent margins around each pose, so its frame
/// tightly bounds the visible cat — head at the top edge, feet at the bottom
/// edge. Every pose therefore seats on a common baseline and callers never
/// hand-tune per-pose offsets.
struct MascotFigure: View {
    let pose: MascotPose
    var size: CGFloat = 104
    var grounding: MascotGrounding = .shadow

    private var visibleHeight: CGFloat {
        self.pose.visibleHeightRatio * self.size
    }

    var body: some View {
        ZStack {
            self.groundingShape
            Mascot(pose: self.pose, size: self.size)
                .padding(.top, -self.pose.topInset * self.size)
                .padding(.bottom, -(1 - self.pose.groundLine) * self.size)
        }
    }

    @ViewBuilder
    private var groundingShape: some View {
        switch self.grounding {
        case .shadow:
            VStack(spacing: 0) {
                Spacer(minLength: 0)
                Ellipse()
                    .fill(Color.tujiInk.opacity(0.16))
                    .frame(width: self.size * self.pose.contactWidth, height: self.size * 0.11)
                    .blur(radius: self.size * 0.045)
            }
            .frame(width: self.size, height: self.visibleHeight)
        case .glow:
            Ellipse()
                .fill(Color.white.opacity(0.18))
                .frame(width: self.size * 0.84, height: self.visibleHeight * 0.94)
                .blur(radius: self.size * 0.13)
        case .none:
            EmptyView()
        }
    }
}

#Preview("Poses") {
    HStack(spacing: Space.s3) {
        ForEach(MascotPose.allCases, id: \.self) { pose in
            VStack {
                Mascot(pose: pose)
                Text(pose.rawValue).font(.tujiLabel)
            }
        }
    }
    .padding()
    .background(.tujiPaper)
}

#Preview("Figures seated on a baseline") {
    VStack(spacing: Space.s5) {
        HStack(alignment: .bottom, spacing: Space.s3) {
            ForEach(MascotPose.allCases, id: \.self) { pose in
                MascotFigure(pose: pose, size: 80)
            }
        }
        HStack(alignment: .bottom, spacing: Space.s3) {
            MascotFigure(pose: .wave, size: 96, grounding: .glow)
            MascotFigure(pose: .cheer, size: 96, grounding: .glow)
            MascotFigure(pose: .peek, size: 96, grounding: .glow)
        }
        .padding(Space.s4)
        .background(.tujiInk, in: .rect(cornerRadius: Radius.r0))
    }
    .padding()
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(.tujiPaper)
}
