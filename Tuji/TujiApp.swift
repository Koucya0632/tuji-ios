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

    @ViewBuilder
    private var rootContent: some View {
        #if DEBUG
        if let screen = AdSnapshotScreen.current {
            AdSnapshotRoot(screen: screen)
        } else {
            RootView()
        }
        #else
        RootView()
        #endif
    }
}

#if DEBUG
private enum AdSnapshotScreen: String {
    case home
    case capture
    case cards
    case review

    static var current: AdSnapshotScreen? {
        ProcessInfo.processInfo.arguments
            .compactMap { arg -> AdSnapshotScreen? in
                guard arg.hasPrefix("--ad-snapshot=") else { return nil }
                return AdSnapshotScreen(rawValue: String(arg.dropFirst("--ad-snapshot=".count)))
            }
            .first
    }
}

private struct AdSnapshotRoot: View {
    let screen: AdSnapshotScreen

    var body: some View {
        Group {
            switch self.screen {
            case .home:
                MainTabsView(user: nil)
            case .capture:
                AdCaptureSnapshotView()
            case .cards:
                AdCardsSnapshotView()
            case .review:
                NavigationStack {
                    ReviewFlowView(queue: Self.reviewQueue)
                }
            }
        }
        .background(.tujiPaper)
    }

    private static var reviewQueue: [StudyQueueItem] {
        let json = """
        [
          {
            "card": {
              "id": "ad-cup-card",
              "cardType": "image_recall",
              "deckKey": "atlas"
            },
            "word": {
              "id": "ad-cup",
              "word": "cup",
              "chinese": "杯子",
              "imageUrl": "http://127.0.0.1:8765/cup.png",
              "pronunciation": "/kʌp/",
              "reading": null,
              "targetLanguage": "en",
              "category": "custom"
            },
            "choices": ["mug", "bowl", "plate"],
            "spellingChoices": null,
            "mastery": 35
          }
        ]
        """
        let data = Data(json.utf8)
        return (try? JSONDecoder().decode([StudyQueueItem].self, from: data)) ?? []
    }
}

private struct AdCaptureSnapshotView: View {
    var body: some View {
        VStack(spacing: 0) {
            TujiSheetHeader(title: Text("拍照新增"))
            VStack(alignment: .leading, spacing: Space.s3) {
                VStack(alignment: .leading, spacing: Space.s2) {
                    Text("拍下身邊的東西")
                        .font(.tujiH3)
                        .foregroundStyle(.tujiInk)
                    Text("拍照後自動 AI 辨識，校正後一鍵生成學習卡片。")
                        .font(.tujiBodySm)
                        .foregroundStyle(.tujiInk3)
                    // Interpolated, not spelled out: "免費版：本月 AI 辨識剩 24／30 次"
                    // is not a catalog key, so the English and Japanese App Store
                    // screenshots carried a line of Traditional Chinese.
                    Text("免費版：本月 AI 辨識剩 \(24)／\(30) 次")
                        .font(.tujiLabel)
                        .foregroundStyle(.tujiInk3)
                }

                BBtn(title: "拍照", fullWidth: true, icon: "camera.fill") {}

                HStack {
                    Image(systemName: "photo.on.rectangle")
                    Text("從相簿選")
                }
                .font(.tujiH3)
                .foregroundStyle(.tujiInk)
                .frame(maxWidth: .infinity)
                .frame(height: 56)
                .background(.tujiPaper2)

                Spacer()
            }
            .padding(.horizontal, Space.s4)
            .padding(.vertical, Space.s3)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(.tujiPaper)
    }
}

private struct AdCardsSnapshotView: View {
    private let words: [CardWord] = [
        CardWord(
            id: "ad-coffee",
            word: "coffee",
            chinese: "咖啡",
            imageUrl: "http://127.0.0.1:8765/coffee.png",
            category: "custom",
            pronunciation: "/ˈkɑːfi/",
            targetLanguage: .en
        ),
        CardWord(
            id: "ad-umbrella",
            word: "umbrella",
            chinese: "雨傘",
            imageUrl: "http://127.0.0.1:8765/umbrella.png",
            category: "custom",
            pronunciation: "/ʌmˈbrelə/",
            targetLanguage: .en
        ),
        CardWord(
            id: "ad-station",
            word: "station",
            chinese: "車站",
            imageUrl: "http://127.0.0.1:8765/station.png",
            category: "custom",
            pronunciation: "/ˈsteɪʃən/",
            targetLanguage: .en
        )
    ]

    var body: some View {
        VStack(spacing: 0) {
            self.header
            self.progressStrip
            self.chipRow
            ScrollView {
                LazyVGrid(
                    columns: [
                        GridItem(.flexible(), spacing: Space.s3),
                        GridItem(.flexible(), spacing: Space.s3)
                    ],
                    spacing: Space.s3
                ) {
                    ForEach(Array(self.words.enumerated()), id: \.element.id) { index, word in
                        WordTile(
                            word: word,
                            showMastery: true,
                            masteryScore: [18, 32, 24][index],
                            nextReviewDate: Calendar.current.date(byAdding: .day, value: index + 1, to: Date())
                        )
                    }
                }
                .padding(.horizontal, Space.s4)
                .padding(.top, Space.s1)
            }
        }
        .background(.tujiPaper)
    }

    private var header: some View {
        HStack {
            Text("圖鑑")
                .font(.tujiH2)
                .foregroundStyle(.tujiInk)
            Spacer()
            Image(systemName: "camera.viewfinder")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(.tujiInk2)
            Image(systemName: "magnifyingglass")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(.tujiInk2)
        }
        .padding(.horizontal, Space.s4)
        .padding(.top, Space.s3)
        .padding(.bottom, Space.s3)
    }

    private var progressStrip: some View {
        HStack(spacing: Space.s3) {
            Image(systemName: "sparkles")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(.tujiTeal)
            VStack(alignment: .leading, spacing: 2) {
                Text("生活物品，自動變單字卡")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.tujiInk)
                Text("剛新增 3 張：咖啡、雨傘、車站")
                    .font(.tujiLabel)
                    .foregroundStyle(.tujiInk3)
            }
            Spacer()
        }
        .padding(.horizontal, Space.s3)
        .padding(.vertical, Space.s3)
        .background(.tujiTealSoft, in: .rect(cornerRadius: Radius.r0))
        .padding(.horizontal, Space.s4)
        .padding(.bottom, Space.s3)
    }

    private var chipRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Space.s2) {
                self.chip("全部", selected: true)
                self.chip("自製圖鑑")
                self.chip("生活")
            }
            .padding(.horizontal, Space.s4)
        }
        .padding(.bottom, Space.s3)
    }

    private func chip(_ label: String, selected: Bool = false) -> some View {
        Text(label)
            .font(.system(size: 13, weight: .bold))
            .foregroundStyle(selected ? .white : .tujiInk2)
            .padding(.horizontal, Space.s3)
            .padding(.vertical, Space.s2)
            .background(selected ? .tujiInk : .tujiPaper, in: .rect(cornerRadius: Radius.r0))
            .overlay(
                Rectangle().stroke(.tujiRule.opacity(selected ? 0 : 0.3), lineWidth: 1)
            )
    }
}
#endif
