// Top-level state switcher. Drives Splash → Welcome → (Push permission?)
// → MainTabs based on AuthService.state + PushNotificationService.

import SwiftUI

struct RootView: View {
    @Environment(AuthService.self) private var auth
    @Environment(PushNotificationService.self) private var push

    var body: some View {
        Group {
            switch auth.state {
            case .checking:
                SplashView()
            case .signedOut:
                WelcomeView()
            case .signedIn(let user):
                if push.hasBeenPrompted {
                    MainTabsView(user: user)
                } else {
                    PushPermissionView(onDone: {
                        // PushNotificationService marks `prompted = true`
                        // before this fires; the next render lands on
                        // MainTabsView automatically because of the
                        // hasBeenPrompted check above.
                    })
                }
            }
        }
        .task { await auth.restoreSession() }
        .animation(.easeInOut(duration: 0.25), value: stateKey)
    }

    private var stateKey: String {
        switch auth.state {
        case .checking: "checking"
        case .signedOut: "signedOut"
        case .signedIn(let u): "signedIn-\(u.id)-\(push.hasBeenPrompted)"
        }
    }
}

#Preview {
    RootView()
        .environment(AuthService.shared)
        .environment(PushNotificationService.shared)
}
