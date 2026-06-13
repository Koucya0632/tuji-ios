// App entry. Wires AuthService + PushNotificationService + OnboardingState
// into the environment so any view can read state via @Environment(...).
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
    @State private var onboarding = OnboardingState.shared
    @State private var cache = LocalCache.shared
    @State private var words = WordsStore.shared
    @State private var categories = CategoriesStore.shared
    @State private var settings = SettingsStore.shared
    @State private var deepLinks = DeepLinkCoordinator.shared

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(auth)
                .environment(push)
                .environment(onboarding)
                .environment(cache)
                .environment(words)
                .environment(categories)
                .environment(settings)
                .environment(deepLinks)
                .environment(\.locale, Self.locale(for: settings.current.uiLang))
                .task {
                    await words.loadIfNeeded()
                    await categories.loadIfNeeded()
                }
                .task { await settings.loadIfNeeded() }
                .task { await push.refreshAuthorization() }
                .onOpenURL { url in
                    // ASWebAuthenticationSession captures the OAuth callback
                    // internally, but forward here as a safety net for any
                    // out-of-band URL the system delivers.
                    GIDSignIn.sharedInstance.handle(url)
                    // Then try our own tuji:// + universal-link handler.
                    if let link = TujiDeepLink.from(url) {
                        deepLinks.receive(link)
                    }
                }
        }
    }

    /// Resolves the server-supplied uiLang code (zh-Hant / zh-Hans / ja)
    /// into a `Locale` so the SwiftUI environment knows which localized
    /// strings to fetch. Unknown codes fall back to zh-Hant.
    private static func locale(for code: String) -> Locale {
        switch code {
        case "zh-Hans": Locale(identifier: "zh-Hans")
        case "ja": Locale(identifier: "ja")
        default: Locale(identifier: "zh-Hant")
        }
    }
}
