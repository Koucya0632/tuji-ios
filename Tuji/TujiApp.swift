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
    init() {
        TujiImagePipeline.install()
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
                .environment(\.locale, Self.locale(for: settings.current.uiLang))
                .task {
                    await words.loadIfNeeded()
                    await categories.loadIfNeeded()
                }
                .task { await settings.loadIfNeeded() }
                .task { await push.refreshAuthorization() }
                // Re-send SRS answers that failed offline (see
                // StudyAnswerOutbox). Launch covers "opened at home with wifi";
                // the foreground trigger covers "came back online mid-day".
                .task { await StudyAnswerOutbox.shared.replay() }
                .onChange(of: scenePhase) { _, phase in
                    guard phase == .active else { return }
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

    /// Resolves the server-supplied uiLang code (zh-Hant / zh-Hans) into a
    /// `Locale` so the SwiftUI environment knows which localized strings to
    /// fetch. Unknown codes — including the retired `ja` UI language — fall
    /// back to zh-Hant.
    private static func locale(for code: String) -> Locale {
        switch code {
        case "zh-Hans": Locale(identifier: "zh-Hans")
        default: Locale(identifier: "zh-Hant")
        }
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
        .background(.tujiBg)
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
        NavigationStack {
            VStack(alignment: .leading, spacing: Space.s4) {
                VStack(alignment: .leading, spacing: Space.s2) {
                    Text("拍下身邊的東西")
                        .font(.tujiH2)
                        .foregroundStyle(.tujiInk)
                    Text("拍照後自動 AI 辨識，校正後一鍵生成學習卡片。")
                        .font(.tujiBody)
                        .foregroundStyle(.tujiInk3)
                    Text("免費版：本月 AI 辨識剩 24／30 次")
                        .font(.tujiCaption)
                        .foregroundStyle(.tujiInk4)
                }

                Button {} label: {
                    HStack {
                        Image(systemName: "camera.fill")
                        Text("拍照")
                    }
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Space.s4)
                    .background(.tujiTeal, in: .rect(cornerRadius: Radius.lg))
                }
                .buttonStyle(.plain)

                HStack {
                    Image(systemName: "photo.on.rectangle")
                    Text("從相簿選")
                }
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.tujiInk)
                .frame(maxWidth: .infinity)
                .padding(.vertical, Space.s4)
                .background(.tujiYellow, in: .rect(cornerRadius: Radius.lg))

                Spacer()
            }
            .padding(.horizontal, Space.s6)
            .padding(.vertical, Space.s4)
            .background(.tujiBg)
            .navigationTitle("拍照新增")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Image(systemName: "xmark")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.tujiInk2)
                }
            }
        }
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
                .padding(.horizontal, Space.s6)
                .padding(.top, Space.s1)
            }
        }
        .background(.tujiBg)
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
        .padding(.horizontal, Space.s6)
        .padding(.top, Space.s4)
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
                    .font(.tujiCaption)
                    .foregroundStyle(.tujiInk3)
            }
            Spacer()
        }
        .padding(.horizontal, Space.s4)
        .padding(.vertical, Space.s3)
        .background(.tujiTealSoft, in: .rect(cornerRadius: Radius.lg))
        .padding(.horizontal, Space.s6)
        .padding(.bottom, Space.s3)
    }

    private var chipRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Space.s2) {
                self.chip("全部", selected: true)
                self.chip("自製圖鑑")
                self.chip("生活")
            }
            .padding(.horizontal, Space.s6)
        }
        .padding(.bottom, Space.s3)
    }

    private func chip(_ label: String, selected: Bool = false) -> some View {
        Text(label)
            .font(.system(size: 13, weight: .bold))
            .foregroundStyle(selected ? .white : .tujiInk2)
            .padding(.horizontal, Space.s4)
            .padding(.vertical, Space.s2)
            .background(selected ? .tujiInk : .tujiCard, in: .capsule)
            .overlay(
                Capsule().stroke(.tujiInk4.opacity(selected ? 0 : 0.3), lineWidth: 1)
            )
    }
}
#endif
