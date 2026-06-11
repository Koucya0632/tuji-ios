// 5-tab post-login shell (§I.9.2).
//
// Each tab owns its own NavigationStack so cross-tab pushes don't
// interfere. Tab bar is custom (not SwiftUI TabView) so we can render
// the elevated center "Tuji" button per design book.
//
// Tabs:
//   today    → TodayView (user-aware)
//   cards    → CardsListView
//   tuji     → TujiCenterView (study landing placeholder)
//   progress → ProgressTabView
//   me       → MeView (account, smoke test, sign-out)

import SwiftUI

struct MainTabsView: View {
    let user: SessionUser?

    @State private var selected: MainTab = .today

    var body: some View {
        ZStack(alignment: .bottom) {
            self.activeTab
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    Color.clear.frame(height: 78)
                }

            TujiTabBar(selected: self.$selected)
                .padding(.horizontal, Space.s4)
                .padding(.bottom, Space.s2)
        }
        .background(.tujiBg)
    }

    @ViewBuilder
    private var activeTab: some View {
        switch self.selected {
        case .today:
            NavigationStack {
                TodayView(user: self.user)
                    .tujiNavDestinations(user: self.user)
            }
        case .cards:
            NavigationStack {
                CardsListView()
                    .tujiNavDestinations(user: self.user)
            }
        case .tuji:
            NavigationStack {
                TujiCenterView()
                    .tujiNavDestinations(user: self.user)
            }
        case .progress:
            NavigationStack {
                ProgressTabView()
                    .tujiNavDestinations(user: self.user)
            }
        case .me:
            NavigationStack {
                MeView(user: self.user)
                    .tujiNavDestinations(user: self.user)
            }
        }
    }
}

private struct TujiTabBar: View {
    @Binding var selected: MainTab

    private let sideTabs: [MainTab] = [.today, .cards]
    private let endTabs: [MainTab] = [.progress, .me]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(self.sideTabs, id: \.self) { tab in
                TabBarButton(tab: tab, isSelected: self.selected == tab) {
                    self.select(tab)
                }
            }
            CenterButton(isSelected: self.selected == .tuji) {
                self.select(.tuji)
            }
            ForEach(self.endTabs, id: \.self) { tab in
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
        self.selected = tab
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

private struct CenterButton: View {
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: self.action) {
            ZStack {
                Circle()
                    .fill(self.isSelected ? .tujiInk : .tujiTeal)
                    .frame(width: 56, height: 56)
                    .shadow(color: .black.opacity(0.15), radius: 6, y: 3)
                Image(systemName: "sparkles")
                    .font(.system(size: 22, weight: .heavy))
                    .foregroundStyle(.white)
            }
        }
        .buttonStyle(.plain)
        .offset(y: -10)
        .frame(width: 64)
    }
}

#Preview("Signed in") {
    MainTabsView(user: SessionUser.tabPreview)
        .environment(AuthService.shared)
        .environment(LocalCache.shared)
        .environment(WordsStore.shared)
        .environment(CategoriesStore.shared)
}

#Preview("Guest") {
    MainTabsView(user: nil)
        .environment(AuthService.shared)
        .environment(LocalCache.shared)
        .environment(WordsStore.shared)
        .environment(CategoriesStore.shared)
}

private extension SessionUser {
    static var tabPreview: SessionUser {
        SessionUser(id: UUID(), email: "preview@tuji.dev", username: "rex", avatar: nil)
    }

    init(id: UUID, email: String?, username: String?, avatar: String?) {
        self.id = id
        self.email = email
        self.username = username
        self.avatar = avatar
    }
}
