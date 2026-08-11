// App entry. Wires AuthService + PushNotificationService + OnboardingState
// into the environment so any view can read state via @Environment(...).
//
// PushAppDelegate is bridged in via @UIApplicationDelegateAdaptor — it's
// the only way to receive APNs registration callbacks from a SwiftUI
// lifecycle.

import GoogleSignIn
import SwiftUI

@main
struct TujiApp: App {
    @UIApplicationDelegateAdaptor(PushAppDelegate.self) private var pushDelegate

    /// Install the custom Nuke pipeline before any LazyImage renders —
    /// ImagePipeline.shared is read at first use, so it must be set
    /// before SwiftUI mounts the view tree.
    @MainActor
    init() {
        TujiImagePipeline.install()
        self.launch = LaunchCoordinator(
            minimumSplashDuration: .milliseconds(600),
            resolveAuthentication: {
                await AuthService.shared.resolveSession()
                if case let .signedIn(user) = AuthService.shared.state {
                    return .signedIn(userID: user.id)
                }
                return .signedOut
            },
            hydrateProfile: {
                await AuthService.shared.refreshResolvedProfile()
            },
            preloadCatalog: {
                let settings = SettingsStore.shared.current
                let context = CatalogContext(
                    settings: settings,
                    userID: nil,
                    includePersonalization: false
                )
                async let words: Void = WordsStore.shared.loadIfNeeded(for: context)
                async let categories: Void = CategoriesStore.shared.loadIfNeeded(for: context)
                _ = await (words, categories)
            },
            finalizeSignedIn: { userID in
                await SettingsStore.shared.loadIfNeeded(for: userID)
                let settings = SettingsStore.shared.current
                let context = CatalogContext(
                    settings: settings,
                    userID: userID,
                    includePersonalization: true
                )
                async let words: Void = WordsStore.shared.loadIfNeeded(for: context)
                async let categories: Void = CategoriesStore.shared.loadIfNeeded(for: context)
                _ = await (words, categories)
            },
            replayOutbox: {
                await StudyAnswerOutbox.shared.replay()
            },
            trackAppOpen: {
                AnalyticsService.shared.track(.appOpen)
            },
            sleep: { duration in
                try? await Task.sleep(for: duration)
            }
        )
    }

    @Environment(\.scenePhase) private var scenePhase

    @State private var auth = AuthService.shared
    @State private var push = PushNotificationService.shared
    @State private var onboarding = OnboardingState.shared
    @State private var cache = LocalCache.shared
    @State private var words = WordsStore.shared
    @State private var categories = CategoriesStore.shared
    @State private var settings = SettingsStore.shared
    @State private var progress = ProgressStore.shared
    @State private var mastery = MasteryStore.shared
    @State private var studyStats = StudyStatsStore.shared
    @State private var studyFocus = StudyFocus.shared
    @State private var deepLinks = DeepLinkCoordinator.shared
    @State private var network = NetworkMonitor.shared
    /// RootView observes this App-owned reference through the environment.
    private let launch: LaunchCoordinator
    @State private var feedRefresh = CommunityFeedRefresh()
    @State private var collectionBookmarks = CollectionBookmarkStore()
    @State private var collectionIdentities = CollectionIdentityStore()

    var body: some Scene {
        WindowGroup {
            self.rootContent
                .environment(auth)
                .environment(push)
                .environment(onboarding)
                .environment(cache)
                .environment(words)
                .environment(categories)
                .environment(settings)
                .environment(progress)
                .environment(mastery)
                .environment(studyStats)
                .environment(studyFocus)
                .environment(deepLinks)
                .environment(network)
                .environment(launch)
                .environment(feedRefresh)
                .environment(collectionBookmarks)
                .environment(collectionIdentities)
                .environment(BlockStore.shared)
                .environment(\.locale, settings.current.uiLanguage.locale)
                // 當前圖鑑語言, supplied once. Every screen that scopes itself to
                // the learning direction reads it from here rather than deriving
                // it again from the store — see TargetLanguageScope.swift.
                .environment(\.targetLanguage, settings.current.learningDirection.targetLanguage)
                .task { await push.refreshAuthorization() }
                // Re-send SRS answers that failed offline (see
                // StudyAnswerOutbox). LaunchCoordinator replays only after a
                // signed-in session resolves, without blocking navigation; the
                // foreground trigger covers "came back online mid-day".
                .onChange(of: scenePhase) { _, phase in
                    guard phase == .active,
                          case .signedIn = auth.state
                    else { return }
                    Task { await StudyAnswerOutbox.shared.replay() }
                }
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

    private var rootContent: some View {
        RootView()
    }
}
