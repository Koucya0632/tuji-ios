// App entry. Wires AuthService + PushNotificationService into the
// environment so any view can read state via @Environment(...).
//
// PushAppDelegate is bridged in via @UIApplicationDelegateAdaptor — it's
// the only way to receive APNs registration callbacks from a SwiftUI
// lifecycle.

import SwiftUI
import GoogleSignIn

@main
struct TujiApp: App {
    @UIApplicationDelegateAdaptor(PushAppDelegate.self) private var pushDelegate

    @State private var auth = AuthService.shared
    @State private var push = PushNotificationService.shared

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(auth)
                .environment(push)
                .task { await push.refreshAuthorization() }
                .onOpenURL { url in
                    // ASWebAuthenticationSession captures the OAuth callback
                    // internally, but forward here as a safety net for any
                    // out-of-band URL the system delivers.
                    GIDSignIn.sharedInstance.handle(url)
                }
        }
    }
}
