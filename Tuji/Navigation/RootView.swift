// Top-level state switcher.
//
//   App launch
//     ├─ AuthService.checking         → SplashView
//     ├─ AuthService.signedOut
//     │    ├─ !introDone              → OnboardingFlow
//     │    └─  introDone              → WelcomeView
//     ├─ AuthService.guest            → SplashView (until content ready)
//     │                                 then MainTabsView(user: nil)
//     │                                 (LocalCache is the source of truth)
//     └─ AuthService.signedIn(user)
//          ├─ !setupDone(user.id)     → SetupView
//          ├─ !contentReady           → SplashView
//          └─ everything ready        → MainTabsView(user: user)
//
// The splash is held over the *main page* (MainTabsView) until the word
// dictionary + category list have finished their first load, so the home
// screen never flashes an empty state on launch. Onboarding / Welcome /
// Setup don't need word data, so they're shown immediately.

import SwiftUI

struct RootView: View {
    @Environment(AuthService.self) private var auth
    @Environment(OnboardingState.self) private var onboarding
    @Environment(WordsStore.self) private var words
    @Environment(CategoriesStore.self) private var categories
    @Environment(NetworkMonitor.self) private var network
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var minimumSplashElapsed = false

    /// The main page's data is ready once both the dictionary and the
    /// category list have completed a load attempt (success or failure —
    /// a failed load still releases the splash and lets MainTabsView show
    /// its own empty / retry state rather than trapping us here).
    private var contentReady: Bool {
        self.words.loaded && self.categories.loaded
    }

    var body: some View {
        ZStack(alignment: .top) {
            content

            if !self.minimumSplashElapsed {
                SplashView()
                    .transition(.opacity)
                    .zIndex(10)
            }

            if self.network.hasStatus, !self.network.isConnected {
                OfflineBanner()
                    .padding(.top, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .zIndex(5)
            }
        }
        .task { await self.runLaunchSequence() }
        .animation(.easeInOut(duration: 0.25), value: stateKey)
        .animation(.easeInOut(duration: 0.25), value: network.isConnected)
    }

    @MainActor
    private func runLaunchSequence() async {
        async let sessionRestore: Void = self.auth.restoreSession()

        if !self.reduceMotion {
            try? await Task.sleep(for: .milliseconds(850))
        }

        guard !Task.isCancelled else { return }
        if self.reduceMotion {
            self.minimumSplashElapsed = true
        } else {
            withAnimation(.easeOut(duration: 0.18)) {
                self.minimumSplashElapsed = true
            }
        }

        await sessionRestore
    }

    @ViewBuilder
    private var content: some View {
        switch auth.state {
        case .checking:
            SplashView()

        case .signedOut:
            if onboarding.learningDirection == nil {
                LearningDirectionOnboardingView()
            } else if onboarding.introDone {
                WelcomeView()
            } else {
                OnboardingFlow()
            }

        case .guest:
            if onboarding.learningDirection == nil {
                LearningDirectionOnboardingView()
            } else if contentReady {
                MainTabsView(user: nil)
            } else {
                SplashView()
            }

        case let .signedIn(user):
            if onboarding.learningDirection == nil {
                LearningDirectionOnboardingView()
            } else if !onboarding.setupDone(for: user.id) {
                SetupView(userId: user.id, onDone: {})
            } else if contentReady {
                MainTabsView(user: user)
            } else {
                SplashView()
            }
        }
    }

    private var stateKey: String {
        switch auth.state {
        case .checking: "checking"
        case .signedOut:
            "signedOut-\(onboarding.learningDirection?.rawValue ?? "unselected")-\(onboarding.introDone)"
        case .guest:
            "guest-\(onboarding.learningDirection?.rawValue ?? "unselected")-ready\(contentReady)"
        case let .signedIn(u):
            "signedIn-\(u.id)-\(onboarding.learningDirection?.rawValue ?? "unselected")-setup\(onboarding.setupDone(for: u.id))-ready\(contentReady)"
        }
    }
}

/// Pinned to the top of the screen (over splash/onboarding/main tabs alike,
/// since RootView is the top-level container) whenever NWPathMonitor reports
/// no connectivity. APIClient's per-request error handling stays reactive —
/// this is a proactive heads-up so a lost connection doesn't look like a
/// silent hang before the first failed request surfaces an error.
private struct OfflineBanner: View {
    var body: some View {
        HStack(spacing: Space.s2) {
            Image(systemName: "wifi.slash")
                .foregroundStyle(.white)
            Text("目前沒有網路連線")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
        }
        .padding(.horizontal, Space.s4)
        .padding(.vertical, Space.s2)
        .background(.tujiCoral, in: .capsule)
        .shadow(color: .black.opacity(0.15), radius: 6, y: 2)
    }
}

#Preview {
    RootView()
        .environment(AuthService.shared)
        .environment(OnboardingState.shared)
        .environment(WordsStore.shared)
        .environment(CategoriesStore.shared)
        .environment(MasteryStore.shared)
        .environment(NetworkMonitor.shared)
}
