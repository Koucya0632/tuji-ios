// Shared NavRoute destination switch. Each tab's NavigationStack attaches
// this so any push of NavRoute resolves consistently.

import SwiftUI

extension View {
    func tujiNavDestinations(user: SessionUser?) -> some View {
        self.navigationDestination(for: NavRoute.self) { route in
            switch route {
            case .cards: CardsListView()
            case .today: TodayView(user: user)
            case .search: SearchView()
            case .favorites: FavoritesView()
            case .settings: SettingsView()
            case let .studyLanding(mode): StudyLandingView(initialMode: mode)
            case let .wordDetail(id): WordDetailView(id: id)
            case let .categoryDetail(id): CategoryView(id: id)
            }
        }
    }
}
