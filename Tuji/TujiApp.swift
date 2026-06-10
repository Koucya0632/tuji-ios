// App entry. Wires AuthService into the environment so any view can read
// auth state via @Environment(AuthService.self).

import SwiftUI
import GoogleSignIn

@main
struct TujiApp: App {
    @State private var auth = AuthService.shared

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(auth)
                .onOpenURL { url in
                    // ASWebAuthenticationSession captures the OAuth callback
                    // internally, but forward here as a safety net for any
                    // out-of-band URL the system delivers.
                    GIDSignIn.sharedInstance.handle(url)
                }
        }
    }
}
