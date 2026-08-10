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

    var body: some View {
        VStack(spacing: 0) {
            self.pager
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            if self.tabBarVisible {
                TujiTabBar(selected: self.$navigator.selected)
                    .tourAnchor(.tabBar)
                    .transition(.move(edge: .bottom))
            }
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
            .scrollIndicators(.hidden)
        }
    }

    @ViewBuilder
    private func page(for tab: MainTab) -> some View {
        switch tab {
        case .today:
            NavigationStack(path: self.$navigator.todayPath) {
                TodayView(user: self.user)
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

    private var tourSteps: [TourStep] {
        TourStep.steps(isGuest: self.user == nil)
    }

    private var tourAnimation: Animation? {
        self.reduceMotion ? nil : .spring(duration: 0.32, bounce: 0.16)
    }

    private func startTourIfNeeded() async {
        guard !self.onboarding.tourDone else { return }
        // Let RootView's minimum-splash overlay clear and the first layout
        // settle before resolving anchors.
        try? await Task.sleep(for: .milliseconds(900))
        guard !self.onboarding.tourDone,
              !self.studyFocus.active,
              self.deepLinks.pending == nil,
              self.tourIndex == nil
        else { return }
        withAnimation(self.tourAnimation) { self.tourIndex = 0 }
    }

    private func advanceTour() {
        guard let index = self.tourIndex else { return }
        let steps = self.tourSteps
        guard index + 1 < steps.count else {
            self.finishTour()
            return
        }
        if steps[index + 1].tab == self.navigator.selected {
            withAnimation(self.tourAnimation) { self.tourIndex = index + 1 }
            return
        }
        // Next step lives on another tab: full dim while the pager slides,
        // then reveal the step once the page has settled.
        self.tourTransitioning = true
        withAnimation(.easeInOut(duration: 0.25)) { self.navigator.selected = steps[index + 1].tab }
        Task {
            try? await Task.sleep(for: .milliseconds(400))
            withAnimation(self.tourAnimation) {
                self.tourIndex = index + 1
                self.tourTransitioning = false
            }
        }
    }

    private func skipTour() {
        self.onboarding.tourDone = true
        self.tourTransitioning = false
        withAnimation(self.tourAnimation) { self.tourIndex = nil }
    }

    private func finishTour() {
        self.onboarding.tourDone = true
        self.tourTransitioning = false
        withAnimation(self.tourAnimation) { self.tourIndex = nil }
        // The tour ends on 圖鑑; the closing card invites the user to start
        // today's study, which lives on 主頁.
        withAnimation(.easeInOut(duration: 0.25)) { self.navigator.selected = .today }
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

    var body: some View {
        HStack(spacing: 0) {
            // `MainTab.allCases`, not a second hand-written list: the bar and
            // the pager have to agree on order or `scrollPosition(id:)` desyncs
            // from the highlighted tab, and nothing made a divergence fail to
            // compile.
            ForEach(MainTab.allCases, id: \.self) { tab in
                TabBarButton(tab: tab, isSelected: self.selected == tab) {
                    self.select(tab)
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
                    .font(.system(size: 20, weight: .semibold))
                Text(self.tab.titleZh)
                    .font(.tujiLabel)
                    // No tracking, unlike every other tujiLabel: the +0.5pt is a
                    // Latin adjustment, and on a full-width CJK glyph it only
                    // buys width. GenSenRounded is wider than the system face.
                    //
                    // Four columns leave ~98pt each, which "コミュニティ" (six
                    // full-width glyphs at 13pt) now clears. The scale factor
                    // stays for the accessibility text sizes, where truncation
                    // is the expected behaviour rather than a layout failure.
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
