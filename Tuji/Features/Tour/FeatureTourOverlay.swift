// Spotlight overlay for the first-run feature tour. Dims the whole
// screen, punches a hole over the current step's target (resolved from
// the TourAnchorKey anchors), and shows a mascot tip card beside it.
// The dim layer hit-tests everywhere, so the app underneath is fully
// interaction-blocked — the highlight is visual only and steps advance
// through 下一步 / 跳過 exclusively.

import SwiftUI

struct FeatureTourOverlay: View {
    let steps: [TourStep]
    let index: Int
    /// True while MainTabsView slides the pager to another tab: keep the
    /// full dim but hide cutout and card so nothing drags across pages.
    let transitioning: Bool
    let anchors: [TourTarget: Anchor<CGRect>]
    let onSkip: () -> Void
    let onNext: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let cutoutPadding: CGFloat = 8

    var body: some View {
        GeometryReader { proxy in
            let step = self.steps[self.index]
            let cutout = self.transitioning ? nil : self.cutoutRect(for: step, in: proxy)

            ZStack {
                self.dim(cutout: cutout, shape: step.shape)
                if let cutout {
                    RoundedRectangle(cornerRadius: self.cornerRadius(for: step.shape, rect: cutout))
                        .stroke(.tujiEye, lineWidth: 2)
                        .frame(width: cutout.width, height: cutout.height)
                        .position(x: cutout.midX, y: cutout.midY)
                        .accessibilityHidden(true)
                }
                if !self.transitioning {
                    self.card(for: step, cutout: cutout, in: proxy)
                        .id(step.id)
                        .transition(
                            self.reduceMotion
                                ? .opacity
                                : .scale(scale: 0.96).combined(with: .opacity)
                        )
                }
            }
        }
        .ignoresSafeArea()
    }

    // MARK: - Dim + cutout

    private func dim(cutout: CGRect?, shape: TourCutoutShape) -> some View {
        ZStack {
            Color.tujiScrim
            if let cutout {
                RoundedRectangle(cornerRadius: self.cornerRadius(for: shape, rect: cutout))
                    .frame(width: cutout.width, height: cutout.height)
                    .position(x: cutout.midX, y: cutout.midY)
                    .blendMode(.destinationOut)
            }
        }
        .compositingGroup()
        .accessibilityHidden(true)
    }

    private func cutoutRect(for step: TourStep, in proxy: GeometryProxy) -> CGRect? {
        guard let target = step.target else { return nil }
        let anchor = self.anchors[target] ?? step.fallback.flatMap { self.anchors[$0] }
        // Missing anchor (unexpected layout variant): render the step as a
        // centered card without a cutout rather than pointing at nothing.
        guard let anchor else { return nil }
        return proxy[anchor].insetBy(dx: -Self.cutoutPadding, dy: -Self.cutoutPadding)
    }

    /// Cutouts are square, like everything else. The one exception is a target
    /// that is itself round (an avatar) — the frame follows the shape it is
    /// framing, otherwise the outline fights its own content.
    private func cornerRadius(for shape: TourCutoutShape, rect: CGRect) -> CGFloat {
        switch shape {
        case .pill: rect.height / 2
        case .rounded: Radius.r0
        }
    }

    // MARK: - Tip card

    @ViewBuilder
    private func card(for step: TourStep, cutout: CGRect?, in proxy: GeometryProxy) -> some View {
        let insets = proxy.safeAreaInsets
        if step.target == nil {
            self.closingCard(for: step)
                .padding(.horizontal, Space.s4)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let cutout {
            let placeBelow = cutout.midY < proxy.size.height * 0.55
            self.tipCard(for: step)
                .padding(.horizontal, Space.s4)
                .frame(
                    maxWidth: .infinity,
                    maxHeight: .infinity,
                    alignment: placeBelow ? .top : .bottom
                )
                .padding(.top, placeBelow ? cutout.maxY + Space.s3 : insets.top + Space.s3)
                .padding(
                    .bottom,
                    placeBelow
                        ? insets.bottom + Space.s3
                        : proxy.size.height - cutout.minY + Space.s3
                )
        } else {
            self.tipCard(for: step)
                .padding(.horizontal, Space.s4)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    /// An ink block, not a card. Every other "this is the important thing right
    /// now" surface in the app is ink, and the cat lying on its top edge is the
    /// same gesture the logo and the Today hero use.
    private func tipCard(for step: TourStep) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(step.title)
                .font(.tujiH3)
                .foregroundStyle(.tujiPaper)
            Text(step.text)
                .font(.tujiBody)
                .foregroundStyle(.tujiPaper.opacity(0.8))
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, Space.s2)

            HStack(spacing: Space.s3) {
                Button(action: self.onSkip) {
                    Text("跳過")
                        .font(.tujiLabel)
                        .tracking(0.5)
                        .foregroundStyle(.tujiPaper.opacity(0.6))
                        .underline()
                        .frame(height: 44)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                Spacer()
                BBtn(title: "下一步", bg: .tujiEye, fg: .tujiInk, action: self.onNext)
            }
            .padding(.top, Space.s4)

            self.dots.padding(.top, Space.s3)
        }
        .padding(Space.s4)
        .padding(.top, Space.s5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.tujiInk)
        .overlay(alignment: .topTrailing) {
            MascotFigure(pose: step.pose, size: 64, grounding: .none)
                .offset(x: -Space.s4, y: -30)
                .accessibilityHidden(true)
        }
        .accessibilityAddTraits(.isModal)
    }

    private func closingCard(for step: TourStep) -> some View {
        // dark: the light variant's accent.opacity(0.32) card lets the
        // dimmed grid underneath bleed through the text.
        MascotCelebrationCard(pose: step.pose, title: step.title, dark: true) {
            VStack(spacing: Space.s3) {
                Text(step.text)
                    .font(.tujiBodySm)
                    .foregroundStyle(.tujiPaper.opacity(0.8))
                    .multilineTextAlignment(.center)
                BBtn(title: "開始使用", bg: .tujiEye, fg: .tujiInk, fullWidth: true, action: self.onNext)
            }
        }
        .accessibilityAddTraits(.isModal)
    }

    private var dots: some View {
        HStack(spacing: Space.s2) {
            ForEach(self.steps) { step in
                Rectangle()
                    .fill(step.id == self.index ? Color.tujiTeal : .tujiPaper2.opacity(0.4))
                    .frame(width: step.id == self.index ? 22 : 7, height: 7)
            }
        }
    }
}

#Preview {
    ZStack {
        Color.tujiPaper.ignoresSafeArea()
        VStack {
            Text("App content")
                .font(.tujiH2)
            Spacer()
        }
        .padding()

        FeatureTourOverlay(
            steps: TourStep.steps(isGuest: false),
            index: 4,
            transitioning: false,
            anchors: [:],
            onSkip: {},
            onNext: {}
        )
    }
}
