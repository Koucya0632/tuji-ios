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
        ZStack {
            content

            if !self.minimumSplashElapsed {
                SplashView()
                    .transition(.opacity)
                    .zIndex(10)
            }
        }
            .task { await self.runLaunchSequence() }
            .animation(.easeInOut(duration: 0.25), value: stateKey)
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

#Preview {
    RootView()
        .environment(AuthService.shared)
        .environment(OnboardingState.shared)
        .environment(WordsStore.shared)
        .environment(CategoriesStore.shared)
        .environment(MasteryStore.shared)
}
