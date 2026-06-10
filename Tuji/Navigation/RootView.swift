// Top-level state switcher. Drives Splash → Welcome → MainTabs based on
// AuthService.state.

import SwiftUI

struct RootView: View {
    @Environment(AuthService.self) private var auth

    var body: some View {
        Group {
            switch auth.state {
            case .checking:
                SplashView()
            case .signedOut:
                WelcomeView()
            case .signedIn(let user):
                MainTabsView(user: user)
            }
        }
        .task { await auth.restoreSession() }
        .animation(.easeInOut(duration: 0.25), value: stateKey)
    }

    private var stateKey: String {
        switch auth.state {
        case .checking: "checking"
        case .signedOut: "signedOut"
        case .signedIn(let u): "signedIn-\(u.id)"
        }
    }
}

#Preview {
    RootView().environment(AuthService.shared)
}
