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

    @State private var selected: MainTab = .today
    @State private var todayPath = NavigationPath()
    @State private var cardsPath = NavigationPath()
    @State private var progressPath = NavigationPath()
    @State private var mePath = NavigationPath()

    var body: some View {
        ZStack(alignment: .bottom) {
            self.pager
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    // Reservation disappears in study mode so the pushed
                    // study views can claim the extra 78pt for the hero.
                    Color.clear.frame(height: self.studyFocus.active ? 0 : 78)
                }

            if !self.studyFocus.active {
                TujiTabBar(selected: self.$selected)
                    .padding(.horizontal, Space.s4)
                    .padding(.bottom, Space.s2)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: self.studyFocus.active)
        .background(.tujiBg)
        .onAppear { self.consumePendingLink() }
        .onChange(of: self.deepLinks.pending) { _, _ in
            self.consumePendingLink()
        }
    }

    private let tabs: [MainTab] = [.today, .cards, .progress, .me]

    // Horizontally-paged container so the four tabs can be switched by
    // swiping left/right, not only by tapping the bar. Each page still owns
    // its NavigationStack, and `selected` stays in sync with the scroll
    // offset via `selectedScrollBinding`.
    //
    // Swiping is allowed only from a tab's root (the 主頁/home level).
    // It is disabled while a study session is active or a detail view is
    // pushed on the current tab, so the page-swipe never fights
    // NavigationStack's own edge-swipe-to-go-back gesture (nor the
    // horizontal scroll inside study's CompleteView).
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

    // Bridges the page scroll offset to `selected` and back: reads as the
    // current tab; a settled swipe writes the newly-centred tab through.
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

    // Push depth of the currently-selected tab. >0 means a detail view is
    // on screen, so tab-swiping is suppressed in favour of back-swipe.
    private var currentPathDepth: Int {
        switch self.selected {
        case .today: self.todayPath.count
        case .cards: self.cardsPath.count
        case .progress: self.progressPath.count
        case .me: self.mePath.count
        }
    }

    private func consumePendingLink() {
        guard let link = deepLinks.consume() else { return }
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
        .environment(DeepLinkCoordinator.shared)
        .environment(StudyFocus.shared)
}

#Preview("Guest") {
    MainTabsView(user: nil)
        .environment(AuthService.shared)
        .environment(LocalCache.shared)
        .environment(WordsStore.shared)
        .environment(CategoriesStore.shared)
        .environment(DeepLinkCoordinator.shared)
        .environment(StudyFocus.shared)
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
