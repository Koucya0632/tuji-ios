// App entry. Wires AuthService into the environment so any view can read
// auth state via @Environment(AuthService.self).

import SwiftUI

@main
struct TujiApp: App {
    @State private var auth = AuthService.shared

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(auth)
        }
    }
}
