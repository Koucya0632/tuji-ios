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
    var visibleHeightRatio: CGFloat { self.groundLine - self.topInset }
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

    private var visibleHeight: CGFloat { self.pose.visibleHeightRatio * self.size }

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
                Text(pose.rawValue).font(.tujiCaption)
            }
        }
    }
    .padding()
    .background(.tujiBg)
}

#Preview("Figures seated on a baseline") {
    VStack(spacing: Space.s8) {
        HStack(alignment: .bottom, spacing: Space.s4) {
            ForEach(MascotPose.allCases, id: \.self) { pose in
                MascotFigure(pose: pose, size: 80)
            }
        }
        HStack(alignment: .bottom, spacing: Space.s4) {
            MascotFigure(pose: .wave, size: 96, grounding: .glow)
            MascotFigure(pose: .cheer, size: 96, grounding: .glow)
            MascotFigure(pose: .peek, size: 96, grounding: .glow)
        }
        .padding(Space.s5)
        .background(.tujiBgInk, in: .rect(cornerRadius: Radius.xl))
    }
    .padding()
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(.tujiBg)
}
