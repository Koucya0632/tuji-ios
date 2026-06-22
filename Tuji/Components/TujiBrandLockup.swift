import SwiftUI

/// The primary Tuji brand lockup. The peek pose overlaps the wordmark card so
/// the mascot and name read as one mark instead of two vertically stacked
/// elements.
struct TujiBrandLockup: View {
    var scale: CGFloat = 1
    var animateEntrance = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var holeOpen = false
    @State private var mascotPresented = false

    private let catSize: CGFloat = 150
    /// Negative spacing lets the paws visibly land on the wordmark card.
    private let gap: CGFloat = -16

    var body: some View {
        let lift = MascotPose.peek.visibleHeightRatio * catSize + gap

        ZStack(alignment: .top) {
            portal
                .offset(y: lift - 30)
                .scaleEffect(
                    x: self.entranceFinished || self.holeOpen ? 1 : 0.58,
                    y: self.entranceFinished || self.holeOpen ? 1 : 0.72
                )
                .opacity(self.entranceFinished || self.holeOpen ? 1 : 0.72)

            MascotFigure(pose: .peek, size: catSize, grounding: .none)
                .scaleEffect(self.entranceFinished || self.mascotPresented ? 1 : 0.82, anchor: .bottom)
                .offset(y: self.entranceFinished || self.mascotPresented ? 0 : lift + 10)
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
        .task(id: self.animateEntrance) {
            await self.playEntranceIfNeeded()
        }
    }

    private var entranceFinished: Bool {
        !self.animateEntrance || self.reduceMotion
    }

    private var portal: some View {
        Ellipse()
            .fill(
                LinearGradient(
                    colors: [.tujiTeal, .tujiTealDark],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .frame(width: 176, height: 48)
            .overlay(
                Ellipse()
                    .stroke(.tujiTealSoft.opacity(0.72), lineWidth: 3)
            )
            .shadow(color: .tujiTealDark.opacity(0.28), radius: 7, y: 5)
    }

    private var wordmarkCard: some View {
        ZStack(alignment: .top) {
            RoundedRectangle(cornerRadius: 24)
                .fill(.tujiTealDark)
                .frame(width: 220, height: 76)
                .offset(y: 5)

            HStack(alignment: .firstTextBaseline, spacing: 0) {
                Text("Tuji")
                    .foregroundStyle(.tujiInk)
                Text(".")
                    .foregroundStyle(.tujiCoral)
            }
            .font(.system(size: 54, weight: .black, design: .rounded))
            .tracking(-2.5)
            .frame(width: 224, height: 78)
            .background(.tujiCard, in: .rect(cornerRadius: 24))
            .overlay(
                RoundedRectangle(cornerRadius: 24)
                    .stroke(.tujiInk.opacity(0.08), lineWidth: 1)
            )
        }
    }

    @MainActor
    private func playEntranceIfNeeded() async {
        guard self.animateEntrance, !self.reduceMotion else {
            self.holeOpen = true
            self.mascotPresented = true
            return
        }

        self.holeOpen = false
        self.mascotPresented = false

        try? await Task.sleep(for: .milliseconds(90))
        guard !Task.isCancelled else { return }

        withAnimation(.easeOut(duration: 0.16)) {
            self.holeOpen = true
        }

        try? await Task.sleep(for: .milliseconds(110))
        guard !Task.isCancelled else { return }

        withAnimation(
            .interpolatingSpring(
                mass: 0.78,
                stiffness: 170,
                damping: 12,
                initialVelocity: 0.7
            )
        ) {
            self.mascotPresented = true
        }
    }
}

#Preview {
    VStack(spacing: Space.s8) {
        TujiBrandLockup(animateEntrance: true)
        TujiBrandLockup(scale: 0.78)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(.tujiBg)
}
