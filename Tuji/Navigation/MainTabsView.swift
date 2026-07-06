// 4-tab post-login shell (§I.9.2).
//
// Each tab owns its own NavigationStack so cross-tab pushes don't
// interfere. Tab bar is custom (not SwiftUI TabView) to preserve the
// floating pill treatment from the design system.
//
// Tabs:
//   today    → TodayView (user-aware)
//   cards    → CardsListView
//   progress → ProgressTabView
//   me       → MeView (account, smoke test, sign-out)

import SwiftUI

struct MainTabsView: View {
    let user: SessionUser?

    @Environment(DeepLinkCoordinator.self) private var deepLinks
    @Environment(StudyFocus.self) private var studyFocus
    @Environment(OnboardingState.self) private var onboarding
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var selected: MainTab = .today
    @State private var todayPath = NavigationPath()
    @State private var cardsPath = NavigationPath()
    @State private var progressPath = NavigationPath()
    @State private var mePath = NavigationPath()

    @State private var tourIndex: Int?
    @State private var tourTransitioning = false

    var body: some View {
        VStack(spacing: 0) {
            self.pager
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            if !self.studyFocus.active {
                TujiTabBar(selected: self.$selected)
                    .tourAnchor(.tabBar)
                    .padding(.horizontal, Space.s4)
                    .padding(.top, Space.s2)
                    .padding(.bottom, Space.s2)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: self.studyFocus.active)
        .background(.tujiBg)
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

    private let tabs: [MainTab] = [.today, .cards, .progress, .me]

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
                    ForEach(self.tabs, id: \.self) { tab in
                        self.page(for: tab)
                            .frame(width: geo.size.width, height: geo.size.height)
                            .id(tab)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.paging)
            .scrollPosition(id: self.selectedScrollBinding, anchor: .center)
            .scrollDisabled(self.studyFocus.active || self.currentPathDepth > 0)
            .scrollIndicators(.hidden)
        }
    }

    @ViewBuilder
    private func page(for tab: MainTab) -> some View {
        switch tab {
        case .today:
            NavigationStack(path: self.$todayPath) {
                TodayView(user: self.user)
                    .tujiNavDestinations(user: self.user)
            }
        case .cards:
            NavigationStack(path: self.$cardsPath) {
                CardsListView()
                    .tujiNavDestinations(user: self.user)
            }
        case .progress:
            NavigationStack(path: self.$progressPath) {
                ProgressTabView()
                    .tujiNavDestinations(user: self.user)
            }
        case .me:
            NavigationStack(path: self.$mePath) {
                MeView(user: self.user)
                    .tujiNavDestinations(user: self.user)
            }
        }
    }

    /// Bridges the page scroll offset to `selected` and back: reads as the
    /// current tab; a settled swipe writes the newly-centred tab through.
    private var selectedScrollBinding: Binding<MainTab?> {
        Binding(
            get: { self.selected },
            set: { newValue in
                if let newValue, newValue != self.selected {
                    self.selected = newValue
                }
            }
        )
    }

    /// Push depth of the currently-selected tab. >0 means a detail view is
    /// on screen, so tab-swiping is suppressed in favour of back-swipe.
    private var currentPathDepth: Int {
        switch self.selected {
        case .today: self.todayPath.count
        case .cards: self.cardsPath.count
        case .progress: self.progressPath.count
        case .me: self.mePath.count
        }
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
        if steps[index + 1].tab == self.selected {
            withAnimation(self.tourAnimation) { self.tourIndex = index + 1 }
            return
        }
        // Next step lives on another tab: full dim while the pager slides,
        // then reveal the step once the page has settled.
        self.tourTransitioning = true
        withAnimation(.easeInOut(duration: 0.25)) { self.selected = steps[index + 1].tab }
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
        withAnimation(.easeInOut(duration: 0.25)) { self.selected = .today }
    }

    private func consumePendingLink() {
        guard let link = deepLinks.consume() else { return }
        // A deep link (e.g. push-notification tap) outranks the tour.
        if self.tourIndex != nil { self.skipTour() }
        self.selected = link.tab
        guard let route = link.route else { return }
        // Append on the next runloop turn so the NavigationStack for the
        // newly-selected tab has time to mount.
        DispatchQueue.main.async {
            switch link.tab {
            case .today: self.todayPath.append(route)
            case .cards: self.cardsPath.append(route)
            case .progress: self.progressPath.append(route)
            case .me: self.mePath.append(route)
            }
        }
    }
}

private struct TujiTabBar: View {
    @Binding var selected: MainTab

    private let tabs: [MainTab] = [.today, .cards, .progress, .me]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(self.tabs, id: \.self) { tab in
                TabBarButton(tab: tab, isSelected: self.selected == tab) {
                    self.select(tab)
                }
            }
        }
        .padding(.horizontal, Space.s2)
        .padding(.vertical, Space.s2)
        .background(.tujiCard, in: .rect(cornerRadius: Radius.pill))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.pill)
                .stroke(.tujiInk4.opacity(0.2), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.06), radius: 8, y: 2)
    }

    private func select(_ tab: MainTab) {
        guard self.selected != tab else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        // Animating the mutation animates the programmatic page scroll so
        // tapping the bar slides to the tab the same way swiping does.
        withAnimation(.easeInOut(duration: 0.25)) {
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
            VStack(spacing: 2) {
                Image(systemName: self.tab.iconName)
                    .font(.system(size: 18, weight: .heavy))
                Text(self.tab.titleZh)
                    .font(.system(size: 10, weight: .heavy))
            }
            .foregroundStyle(self.isSelected ? .tujiTeal : .tujiInk4)
            .frame(maxWidth: .infinity)
            .padding(.vertical, Space.s2)
        }
        .buttonStyle(.plain)
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
