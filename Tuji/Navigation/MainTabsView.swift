// 4-tab post-login shell: 今天 / 圖鑑 / 物見 / 我.
//
// Each tab owns its own NavigationStack so cross-tab pushes don't interfere.
// The bar is custom (not SwiftUI TabView) so it can be an ink block rather than
// a translucent system bar.
//
// Tabs:
//   today     → TodayView (user-aware)
//   cards     → CardsListView — all the words, filtered by source
//   community → AtlasPublicFeedView — other people's collections
//   me        → MeView — what you have accumulated (absorbed the 進度 tab)

import SwiftUI

struct MainTabsView: View {
    let user: SessionUser?

    @Environment(DeepLinkCoordinator.self) private var deepLinks
    @Environment(StudyFocus.self) private var studyFocus
    @Environment(OnboardingState.self) private var onboarding
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Owned here, reachable everywhere: see `TabNavigator` for why the paths
    /// could not stay private to this View.
    @State private var navigator = TabNavigator()

    @State private var tourIndex: Int?
    @State private var tourTransitioning = false

    /// Presented from the shell, not from 圖鑑, because the bar that opens it is
    /// on every tab. It was `@State` on `CardsListView`, which is why the only
    /// way to reach 拍照 was to be standing in 圖鑑 first.
    @State private var showCapture = false

    var body: some View {
        VStack(spacing: 0) {
            self.pager
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            if self.tabBarVisible {
                TujiTabBar(
                    selected: self.$navigator.selected,
                    onCapture: { self.showCapture = true }
                )
                .tourAnchor(.tabBar)
                .transition(.move(edge: .bottom))
            }
        }
        .fullScreenCover(isPresented: self.$showCapture) {
            AtlasCaptureView()
        }
        // Every pushed screen needs it: a feature screen that wants to open a
        // destination pushes a route through this rather than constructing the
        // screen itself.
        .environment(self.navigator)
        .animation(Motion.ease(Motion.d2), value: self.tabBarVisible)
        .background(.tujiPaper)
        .allowsHitTesting(self.tourIndex == nil)
        .accessibilityHidden(self.tourIndex != nil)
        .overlayPreferenceValue(TourAnchorKey.self) { anchors in
            if let index = self.tourIndex, !self.studyFocus.active {
                FeatureTourOverlay(
                    steps: self.tourSteps,
                    index: index,
                    transitioning: self.tourTransitioning,
                    anchors: anchors,
                    onSkip: self.skipTour,
                    onNext: self.advanceTour
                )
                .transition(.opacity)
            }
        }
        .onAppear { self.consumePendingLink() }
        .onChange(of: self.deepLinks.pending) { _, _ in
            self.consumePendingLink()
        }
        .task { await self.startTourIfNeeded() }
        // 更新提示掛在殼上，不在任何一個分頁裡：它跟使用者站在哪一頁無關。
        // 導覽正在跑的時候不會出現 —— 見 `AppUpdatePolicy.mayPresent`。
        .appUpdatePrompt(tourRunning: self.tourIndex != nil)
    }

    /// Horizontally-paged container so the four tabs can be switched by
    /// swiping left/right, not only by tapping the bar. Each page still owns
    /// its NavigationStack, and `selected` stays in sync with the scroll
    /// offset via `selectedScrollBinding`.
    ///
    /// Swiping is allowed only from a tab's root (the 主頁/home level).
    /// It is disabled while a study session is active or a detail view is
    /// pushed on the current tab, so the page-swipe never fights
    /// NavigationStack's own edge-swipe-to-go-back gesture (nor the
    /// horizontal scroll inside study's CompleteView).
    private var pager: some View {
        GeometryReader { geo in
            ScrollView(.horizontal) {
                HStack(spacing: 0) {
                    ForEach(MainTab.allCases, id: \.self) { tab in
                        self.page(for: tab)
                            .frame(width: geo.size.width, height: geo.size.height)
                            .id(tab)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.paging)
            .scrollPosition(id: self.selectedScrollBinding, anchor: .center)
            .scrollDisabled(
                !TabShellDecisions.swipeEnabled(
                    currentTabAtRoot: self.navigator.currentTabAtRoot,
                    studyFocusActive: self.studyFocus.active
                )
            )
            // Horizontal only. `scrollIndicators` reads from the environment, so
            // it applies to *every* scroll view below it — and this one sits
            // above all four tabs. Unqualified, it was hiding the vertical bar
            // in 圖鑑, 今天, 我 and 物見 as a side effect of hiding the pager's
            // own, which is why nothing in the app had a scroll position to read.
            .scrollIndicators(.hidden, axes: .horizontal)
        }
    }

    @ViewBuilder
    private func page(for tab: MainTab) -> some View {
        switch tab {
        case .today:
            NavigationStack(path: self.$navigator.todayPath) {
                // No `user:` — 今天 reads every identity question through
                // `ViewerIdentity`, and the parameter it was still being handed
                // was referenced nowhere in its body.
                TodayView()
                    .tujiNavDestinations(user: self.user)
                    .tracksStackRoot(self.binding(for: .today))
            }
        case .cards:
            NavigationStack(path: self.$navigator.cardsPath) {
                CardsListView(sourceRequest: self.$navigator.cardsSourceRequest)
                    .tujiNavDestinations(user: self.user)
                    .tracksStackRoot(self.binding(for: .cards))
            }
        case .community:
            NavigationStack(path: self.$navigator.communityPath) {
                AtlasPublicFeedView()
                    .tujiNavDestinations(user: self.user)
                    .tracksStackRoot(self.binding(for: .community))
            }
        case .me:
            NavigationStack(path: self.$navigator.mePath) {
                MeView(user: self.user)
                    .tujiNavDestinations(user: self.user)
                    .tracksStackRoot(self.binding(for: .me))
            }
        }
    }

    private func binding(for tab: MainTab) -> Binding<Bool> {
        Binding(
            get: { self.navigator.atRoot[tab] ?? true },
            set: { self.navigator.atRoot[tab] = $0 }
        )
    }

    /// Bridges the page scroll offset to `selected` and back: reads as the
    /// current tab; a settled swipe writes the newly-centred tab through.
    private var selectedScrollBinding: Binding<MainTab?> {
        Binding(
            get: { self.navigator.selected },
            set: { newValue in
                if let newValue, newValue != self.navigator.selected {
                    self.navigator.selected = newValue
                }
            }
        )
    }

    /// The floating bar steps aside for a focused study session, and for
    /// anything opened from 我 or 物見: both tabs are hubs of entry points, and
    /// a screen opened from one owns the window until the user comes back.
    ///
    /// A different policy from the swipe guard, over the same signal — 今天 and
    /// 圖鑑 keep their bar through a push, because a word detail is a place you
    /// come back from, not a window you are handed.
    private var tabBarVisible: Bool {
        TabShellDecisions.tabBarVisible(
            selected: self.navigator.selected,
            currentTabAtRoot: self.navigator.currentTabAtRoot,
            studyFocusActive: self.studyFocus.active
        )
    }

    // MARK: - First-run feature tour

    /// The index machine and its branches — see `FeatureTourFlow`. What stays
    /// here is the animation, the two beats, and the anchor resolution that
    /// cannot live anywhere else.
    private var tour: FeatureTourFlow {
        FeatureTourFlow(isGuest: self.user == nil)
    }

    private var tourSteps: [TourStep] {
        self.tour.steps
    }

    private var tourAnimation: Animation? {
        self.reduceMotion ? nil : .spring(duration: 0.32, bounce: 0.16)
    }

    private func startTourIfNeeded() async {
        guard !self.onboarding.tourDone else { return }
        // Let RootView's minimum-splash overlay clear and the first layout
        // settle before resolving anchors. Re-asked afterwards, because all
        // four conditions can change while we wait.
        try? await Task.sleep(for: .milliseconds(900))
        guard FeatureTourFlow.mayStart(
            tourDone: self.onboarding.tourDone,
            studyFocusActive: self.studyFocus.active,
            hasPendingLink: self.deepLinks.pending != nil,
            alreadyRunning: self.tourIndex != nil
        )
        else { return }
        withAnimation(self.tourAnimation) { self.tourIndex = 0 }
    }

    private func advanceTour() {
        guard let index = self.tourIndex else { return }
        switch self.tour.advance(from: index, showing: self.navigator.selected) {
        case .finish:
            self.finishTour()
        case let .show(next):
            withAnimation(self.tourAnimation) { self.tourIndex = next }
        case let .crossTab(tab, next):
            // Full dim while the pager slides, then reveal once it has settled.
            self.tourTransitioning = true
            withAnimation(.easeInOut(duration: 0.25)) { self.navigator.selected = tab }
            Task {
                try? await Task.sleep(for: .milliseconds(400))
                withAnimation(self.tourAnimation) {
                    self.tourIndex = next
                    self.tourTransitioning = false
                }
            }
        }
    }

    private func skipTour() {
        self.endTour(landingOn: nil)
    }

    private func finishTour() {
        self.endTour(landingOn: FeatureTourFlow.tabAfterFinishing)
    }

    /// Skipping and finishing differ in exactly one thing: where the reader is
    /// left. They were two near-identical bodies for that one line.
    private func endTour(landingOn tab: MainTab?) {
        self.onboarding.tourDone = true
        self.tourTransitioning = false
        withAnimation(self.tourAnimation) { self.tourIndex = nil }
        if let tab {
            withAnimation(.easeInOut(duration: 0.25)) { self.navigator.selected = tab }
        }
    }

    private func consumePendingLink() {
        let effect = TabShellDecisions.pendingLinkEffect(
            pending: self.deepLinks.pending,
            isSignedIn: self.user != nil,
            tourActive: self.tourIndex != nil
        )
        switch effect {
        // Held, not consumed: the signed-in shell picks it up after sign-in.
        case .hold, .none: return
        case let .apply(applied):
            _ = self.deepLinks.consume()
            if applied.skipTour { self.skipTour() }
            // Tab first, then the push on the next runloop turn so the newly
            // selected tab's NavigationStack has time to mount.
            self.navigator.select(applied.tab)
            if let source = applied.cardsSource { self.navigator.cardsSourceRequest = source }
            guard applied.route != nil else { return }
            DispatchQueue.main.async { self.navigator.applyPush(applied) }
        }
    }
}

private extension View {
    /// Reports whether this view — the root of a `NavigationStack` — is the
    /// screen currently on show. A push covers the root (`onDisappear`), a pop
    /// back uncovers it (`onAppear`); switching pages in the tab pager does
    /// neither, since every page stays mounted in the same `HStack`.
    func tracksStackRoot(_ isShowing: Binding<Bool>) -> some View {
        self
            .onAppear { isShowing.wrappedValue = true }
            .onDisappear { isShowing.wrappedValue = false }
    }
}

/// The tab bar — flush to the bottom, full width, ink.
///
/// The floating white capsule it replaces needed a shadow to read as floating,
/// and the system has no shadow any more. More usefully: a strip of ink along
/// the bottom of every screen presses the whole page onto the paper, and is the
/// anchor for the two-layer rule — every screen ends in the same language.
///
/// Selection is a 3pt 瞳黃 bar on the item's top edge, not a pill and not a dot.
/// Both of those are rounded vocabulary, and 瞳黃 is exactly the right meaning
/// here: it answers "where are you" continuously.
private struct TujiTabBar: View {
    @Binding var selected: MainTab
    let onCapture: () -> Void

    /// 拍照 sits after this tab, which puts it in the middle of the bar.
    private static let captureFollows: MainTab = .cards

    var body: some View {
        HStack(spacing: 0) {
            // `MainTab.allCases`, not a second hand-written list: the bar and
            // the pager have to agree on order or `scrollPosition(id:)` desyncs
            // from the highlighted tab, and nothing made a divergence fail to
            // compile. The capture slot is interleaved rather than added to the
            // enum, so the pager still pages over exactly the tabs.
            ForEach(MainTab.allCases, id: \.self) { tab in
                TabBarButton(tab: tab, isSelected: self.selected == tab) {
                    self.select(tab)
                }
                if tab == Self.captureFollows {
                    CaptureBarButton(action: self.onCapture)
                        .tourAnchor(.capture)
                }
            }
        }
        .background(.tujiInk)
        // The ink runs on past the home indicator; without this the bar stops at
        // the safe-area line and leaves a strip of paper under it.
        .background(Color.tujiInk.ignoresSafeArea(edges: .bottom))
    }

    private func select(_ tab: MainTab) {
        guard self.selected != tab else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        // Animating the mutation animates the programmatic page scroll so
        // tapping the bar slides to the tab the same way swiping does.
        withAnimation(Motion.ease(Motion.d2)) {
            self.selected = tab
        }
    }
}

private struct TabBarButton: View {
    let tab: MainTab
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: self.action) {
            VStack(spacing: Space.s1) {
                Image(systemName: self.tab.iconName)
                    .font(.tujiIcon(20, weight: .semibold))
                Text(self.tab.titleZh)
                    .font(.tujiLabel)
                    // No tracking, unlike every other tujiLabel: the +0.5pt is a
                    // Latin adjustment, and on a full-width CJK glyph it only
                    // buys width. GenSenRounded is wider than the system face.
                    //
                    // Five columns leave ~80pt each. The longest label is now
                    // "マイページ" — five full-width glyphs at 13pt, ~65pt — so it
                    // clears. (This note used to budget for "コミュニティ" at
                    // ~78pt, a label that stopped existing when 社群 became
                    // 物見.) The scale factor stays for the accessibility text
                    // sizes, where truncation is the expected behaviour rather
                    // than a layout failure.
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .foregroundStyle(.tujiPaper.opacity(self.isSelected ? 1 : 0.6))
            .frame(maxWidth: .infinity)
            .frame(height: 64)
            .overlay(alignment: .top) {
                Rectangle()
                    .fill(.tujiCurrent)
                    .frame(height: Border.bw3)
                    .opacity(self.isSelected ? 1 : 0)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        // The icon and the label were separate accessibility elements next to
        // the button, so each tab was announced three times — and once wrongly,
        // because an unlabelled SF Symbol carries the system's own name for it:
        // 今天 read as 「調高亮度」 (sun.max.fill) and 圖鑑 as 「書架」
        // (books.vertical.fill). Collapse the button into one element that says
        // the tab's name and nothing else.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(self.tab.titleZh))
        .accessibilityAddTraits(self.isSelected ? [.isSelected] : [])
    }
}

/// 拍照, in the middle of the bar — the mascot's eye as a shutter.
///
/// Deliberately *not* a fifth `MainTab`: it is something you do, not a place
/// you are, and making it a tab would hand it a `NavigationPath`, an `atRoot`
/// entry, a pager page and a deep-link target — four pieces of navigation state
/// for a screen that is presented as a cover and dismissed.
///
/// It lived in the 圖鑑 header before this, which is the wrong home for an
/// action nobody plans: you photograph a thing because it is in front of you
/// now, and reaching it meant switching tabs and then reaching the top-right
/// corner — the hardest place on a 6" phone for the thumb already holding it.
///
/// **A mark, not a slot.** It first arrived here as a full-height yellow
/// rectangle, which made it the loudest of five slots but still, unmistakably,
/// one of five slots — a tab that happened to be painted. `MascotEye` is a
/// different kind of object: round where everything around it is square, drawn
/// where everything around it is set. That is what separates it, not its
/// colour. Its ground stays ink like its neighbours' precisely so the eye is
/// the only figure.
///
/// The cost, stated plainly: an eye does not say "camera" the way
/// `camera.viewfinder` did. What carries the meaning instead is the shape it
/// shares with a lens, the tour's third step, and the accessibility label —
/// which is now doing real work rather than translating a glyph.
private struct CaptureBarButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: self.action) {
            MascotEye(size: 44)
                .frame(maxWidth: .infinity)
                .frame(height: 64)
                // The whole slot is the target, not just the 44pt circle: a
                // round button in a bar is a smaller tap area than the row it
                // sits in, and the row is what the thumb aims at.
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("拍照收字"))
        .accessibilityAddTraits(.isButton)
    }
}

#Preview("Signed in") {
    MainTabsView(user: SessionUser.tabPreview)
        .environment(AuthService.shared)
        .environment(LocalCache.shared)
        .environment(WordsStore.shared)
        .environment(CategoriesStore.shared)
        .environment(MasteryStore.shared)
        .environment(DeepLinkCoordinator.shared)
        .environment(StudyFocus.shared)
        .environment(OnboardingState.shared)
}

#Preview("Guest") {
    MainTabsView(user: nil)
        .environment(AuthService.shared)
        .environment(LocalCache.shared)
        .environment(WordsStore.shared)
        .environment(CategoriesStore.shared)
        .environment(MasteryStore.shared)
        .environment(DeepLinkCoordinator.shared)
        .environment(StudyFocus.shared)
        .environment(OnboardingState.shared)
}

private extension SessionUser {
    static var tabPreview: SessionUser {
        SessionUser(id: UUID(), email: "preview@tuji.dev", username: "rex", avatar: nil)
    }

    init(id: UUID, email: String?, username: String?, avatar: String?) {
        self.id = id
        self.email = email
        self.username = username
        self.nickname = nil
        self.avatar = avatar
    }
}
