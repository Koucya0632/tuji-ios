// Shared NavRoute destination switch. Each tab's NavigationStack attaches
// this so any push of NavRoute resolves consistently.

import SwiftUI

extension View {
    func tujiNavDestinations(user: SessionUser?) -> some View {
        self.navigationDestination(for: NavRoute.self) { route in
            switch route {
            case .cards: CardsListView()
            case .today: TodayView(user: user)
            case let .search(query): SearchView(initialQuery: query)
            case .favorites: FavoritesView()
            case .settings: SettingsView()
            case .atlasManage: AtlasManageView()
            case .studyCategories: StudyCategoriesPickerView()
            case let .studyLanding(mode): StudyLauncherView(mode: mode)
            case let .wordDetail(id): WordDetailView(id: id)
            case let .categoryDetail(id): CategoryView(id: id)
            }
        }
    }
}
