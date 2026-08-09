import SwiftUI

/// The primary Tuji brand lockup. The peek pose overlaps the wordmark card so
/// the mascot and name read as one mark instead of two vertically stacked
/// elements.
struct TujiBrandLockup: View {
    enum Entrance: Hashable {
        case finished
        case animated
        case start
    }

    var scale: CGFloat = 1
    private let entrance: Entrance
    private let reduceMotionOverride: Bool?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var holeOpen = false
    @State private var mascotPresented = false

    private let catSize: CGFloat = 150
    /// Negative spacing lets the paws visibly land on the wordmark card.
    private let gap: CGFloat = -16

    init(
        scale: CGFloat = 1,
        animateEntrance: Bool = false,
        reduceMotionOverride: Bool? = nil
    ) {
        self.scale = scale
        self.entrance = animateEntrance ? .animated : .finished
        self.reduceMotionOverride = reduceMotionOverride
    }

    /// Used to render the native launch image from the exact same geometry as
    /// the first animated SwiftUI frame. Production callers normally use the
    /// `animateEntrance` initializer above.
    init(
        scale: CGFloat = 1,
        entrance: Entrance,
        reduceMotionOverride: Bool? = nil
    ) {
        self.scale = scale
        self.entrance = entrance
        self.reduceMotionOverride = reduceMotionOverride
    }

    var body: some View {
        let lift = MascotPose.peek.visibleHeightRatio * catSize + gap

        ZStack(alignment: .top) {
            portal
                .offset(y: lift - 30)
                .scaleEffect(
                    x: self.entranceFinished || self.holeOpen ? 1 : 0.58,
                    y: self.entranceFinished || self.holeOpen ? 1 : 0.72
                )

            MascotFigure(pose: .peek, size: catSize, grounding: .none)
                .scaleEffect(self.entranceFinished || self.mascotPresented ? 1 : 0.82, anchor: .bottom)
                .offset(y: self.entranceFinished || self.mascotPresented ? 0 : lift + 10)
                .opacity(self.entranceFinished || self.mascotPresented ? 1 : 0)
                .frame(width: catSize, height: lift + 17, alignment: .top)
                .clipped()

            wordmarkCard
                .padding(.top, lift)
        }
        .frame(width: 232, height: 230)
        .scaleEffect(scale)
        .frame(width: 232 * scale, height: 230 * scale)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Tuji")
        .task(id: self.entrance) {
            await self.playEntranceIfNeeded()
        }
    }

    private var entranceFinished: Bool {
        switch self.entrance {
        case .finished:
            true
        case .animated:
            self.effectiveReduceMotion
        case .start:
            false
        }
    }

    private var effectiveReduceMotion: Bool {
        self.reduceMotionOverride ?? self.reduceMotion
    }

    private var portal: some View {
        Ellipse()
            .fill(
                LinearGradient(
                    colors: [.tujiBrandSecondary.opacity(0.78), .tujiBrandSecondary],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .frame(width: 176, height: 48)
            .shadow(color: .tujiBrandSecondary.opacity(0.28), radius: 7, y: 5)
    }

    private var wordmarkCard: some View {
        ZStack(alignment: .top) {
            RoundedRectangle(cornerRadius: 24)
                .fill(.tujiInk.opacity(0.24))
                .frame(width: 220, height: 76)
                .offset(y: 5)

            HStack(alignment: .firstTextBaseline, spacing: 0) {
                Text("Tuji")
                    .foregroundStyle(.tujiBrandPrimary)
                Text(".")
                    .foregroundStyle(.tujiAlert)
            }
            .font(.system(size: 54, weight: .black, design: .rounded))
            .tracking(-2.5)
            .frame(width: 224, height: 78)
            .background(.tujiBrandSecondary, in: .rect(cornerRadius: 24))
        }
    }

    @MainActor
    private func playEntranceIfNeeded() async {
        switch self.entrance {
        case .start:
            self.holeOpen = false
            self.mascotPresented = false
            return
        case .finished:
            self.holeOpen = true
            self.mascotPresented = true
            return
        case .animated where self.effectiveReduceMotion:
            self.holeOpen = true
            self.mascotPresented = true
            return
        case .animated:
            break
        }

        self.holeOpen = false
        self.mascotPresented = false

        // Hold the exact native launch frame briefly before opening the portal.
        // The full entrance settles before LaunchCoordinator's 600ms minimum.
        try? await Task.sleep(for: .milliseconds(70))
        guard !Task.isCancelled else { return }

        withAnimation(.easeOut(duration: 0.14)) {
            self.holeOpen = true
        }

        try? await Task.sleep(for: .milliseconds(100))
        guard !Task.isCancelled else { return }

        withAnimation(.spring(duration: 0.34, bounce: 0.28)) {
            self.mascotPresented = true
        }
    }
}

#Preview {
    VStack(spacing: Space.s5) {
        TujiBrandLockup(animateEntrance: true)
        TujiBrandLockup(scale: 0.78)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(.tujiPaper)
}
