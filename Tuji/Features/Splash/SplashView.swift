// Shown while AuthService is restoring session (~ 100-300ms typical).

import SwiftUI

struct SplashView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var loaderVisible = false

    var body: some View {
        VStack(spacing: Space.s6) {
            TujiBrandLockup(animateEntrance: true)

            ProgressView()
                .tint(.tujiTeal)
                .controlSize(.small)
                .opacity(self.loaderVisible ? 1 : 0)
                .offset(y: self.loaderVisible ? 0 : 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.tujiBg)
        .task {
            if self.reduceMotion {
                self.loaderVisible = true
                return
            }

            try? await Task.sleep(for: .milliseconds(680))
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.18)) {
                self.loaderVisible = true
            }
        }
    }
}

#Preview { SplashView() }
