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
//          ├─ !push.hasBeenPrompted   → PushPermissionView
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
    @Environment(PushNotificationService.self) private var push
    @Environment(OnboardingState.self) private var onboarding
    @Environment(WordsStore.self) private var words
    @Environment(CategoriesStore.self) private var categories

    /// The main page's data is ready once both the dictionary and the
    /// category list have completed a load attempt (success or failure —
    /// a failed load still releases the splash and lets MainTabsView show
    /// its own empty / retry state rather than trapping us here).
    private var contentReady: Bool {
        self.words.loaded && self.categories.loaded
    }

    var body: some View {
        content
            .task { await auth.restoreSession() }
            .animation(.easeInOut(duration: 0.25), value: stateKey)
    }

    @ViewBuilder
    private var content: some View {
        switch auth.state {
        case .checking:
            SplashView()

        case .signedOut:
            if onboarding.introDone {
                WelcomeView()
            } else {
                OnboardingFlow()
            }

        case .guest:
            if contentReady {
                MainTabsView(user: nil)
            } else {
                SplashView()
            }

        case let .signedIn(user):
            if !onboarding.setupDone(for: user.id) {
                SetupView(userId: user.id, onDone: {})
            } else if !push.hasBeenPrompted {
                PushPermissionView(onDone: {})
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
        case .signedOut: "signedOut-\(onboarding.introDone)"
        case .guest: "guest-ready\(contentReady)"
        case let .signedIn(u):
            "signedIn-\(u.id)-setup\(onboarding.setupDone(for: u.id))-push\(push.hasBeenPrompted)-ready\(contentReady)"
        }
    }
}

#Preview {
    RootView()
        .environment(AuthService.shared)
        .environment(PushNotificationService.shared)
        .environment(OnboardingState.shared)
        .environment(WordsStore.shared)
        .environment(CategoriesStore.shared)
}
