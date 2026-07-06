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
                        .stroke(.tujiYellow, lineWidth: 2)
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
            Color.tujiBgInk.opacity(0.55)
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

    private func cornerRadius(for shape: TourCutoutShape, rect: CGRect) -> CGFloat {
        switch shape {
        case let .rounded(radius): radius
        case .pill: rect.height / 2
        }
    }

    // MARK: - Tip card

    @ViewBuilder
    private func card(for step: TourStep, cutout: CGRect?, in proxy: GeometryProxy) -> some View {
        let insets = proxy.safeAreaInsets
        if step.target == nil {
            self.closingCard(for: step)
                .padding(.horizontal, Space.s6)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let cutout {
            let placeBelow = cutout.midY < proxy.size.height * 0.55
            self.tipCard(for: step)
                .padding(.horizontal, Space.s5)
                .frame(
                    maxWidth: .infinity,
                    maxHeight: .infinity,
                    alignment: placeBelow ? .top : .bottom
                )
                .padding(.top, placeBelow ? cutout.maxY + Space.s4 : insets.top + Space.s4)
                .padding(
                    .bottom,
                    placeBelow
                        ? insets.bottom + Space.s4
                        : proxy.size.height - cutout.minY + Space.s4
                )
        } else {
            self.tipCard(for: step)
                .padding(.horizontal, Space.s5)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func tipCard(for step: TourStep) -> some View {
        VStack(alignment: .leading, spacing: Space.s4) {
            HStack(alignment: .top, spacing: Space.s3) {
                MascotFigure(pose: step.pose, size: 64)
                VStack(alignment: .leading, spacing: Space.s1) {
                    Text(step.title)
                        .font(.tujiH4)
                        .foregroundStyle(.tujiInk)
                    Text(step.text)
                        .font(.tujiBody)
                        .foregroundStyle(.tujiInk2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            HStack(spacing: Space.s3) {
                self.dots
                Spacer()
                Button(action: self.onSkip) {
                    Text("跳過")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.tujiInk3)
                        .padding(.vertical, Space.s2)
                        .padding(.horizontal, Space.s2)
                }
                .buttonStyle(.plain)
                BBtn(title: "下一步", bg: .tujiTeal, fg: .white, action: self.onNext)
            }
        }
        .padding(Space.s5)
        .background(.tujiCard, in: .rect(cornerRadius: Radius.xl))
        .tujiCardShadow()
        .frame(maxWidth: 440)
        .accessibilityAddTraits(.isModal)
    }

    private func closingCard(for step: TourStep) -> some View {
        // dark: the light variant's accent.opacity(0.32) card lets the
        // dimmed grid underneath bleed through the text.
        MascotCelebrationCard(pose: step.pose, title: step.title, dark: true) {
            VStack(spacing: Space.s4) {
                Text(step.text)
                    .font(.tujiBody)
                    .foregroundStyle(.white.opacity(0.75))
                    .multilineTextAlignment(.center)
                BBtn(title: "開始使用", bg: .tujiTeal, fg: .white, fullWidth: true, action: self.onNext)
            }
        }
        .accessibilityAddTraits(.isModal)
    }

    private var dots: some View {
        HStack(spacing: Space.s2) {
            ForEach(self.steps) { step in
                Capsule()
                    .fill(step.id == self.index ? Color.tujiTeal : .tujiInk4.opacity(0.4))
                    .frame(width: step.id == self.index ? 22 : 7, height: 7)
            }
        }
    }
}

#Preview {
    ZStack {
        Color.tujiBg.ignoresSafeArea()
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
