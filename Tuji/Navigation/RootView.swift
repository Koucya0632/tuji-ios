// Top-level state switcher.
//
//   App launch
//     ├─ AuthService.checking         → SplashView
//     ├─ AuthService.signedOut
//     │    ├─ !introDone              → OnboardingFlow
//     │    └─  introDone              → WelcomeView
//     ├─ AuthService.guest            → MainTabsView(user: nil)
//     │                                 (LocalCache is the source of truth)
//     └─ AuthService.signedIn(user)
//          ├─ !setupDone(user.id)     → SetupView
//          ├─ !push.hasBeenPrompted   → PushPermissionView
//          └─ everything ready        → MainTabsView(user: user)

import SwiftUI

struct RootView: View {
    @Environment(AuthService.self) private var auth
    @Environment(PushNotificationService.self) private var push
    @Environment(OnboardingState.self) private var onboarding

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
            MainTabsView(user: nil)

        case .signedIn(let user):
            if !onboarding.setupDone(for: user.id) {
                SetupView(userId: user.id, onDone: {})
            } else if !push.hasBeenPrompted {
                PushPermissionView(onDone: {})
            } else {
                MainTabsView(user: user)
            }
        }
    }

    private var stateKey: String {
        switch auth.state {
        case .checking: "checking"
        case .signedOut: "signedOut-\(onboarding.introDone)"
        case .guest: "guest"
        case .signedIn(let u):
            "signedIn-\(u.id)-setup\(onboarding.setupDone(for: u.id))-push\(push.hasBeenPrompted)"
        }
    }
}

#Preview {
    RootView()
        .environment(AuthService.shared)
        .environment(PushNotificationService.shared)
        .environment(OnboardingState.shared)
}
