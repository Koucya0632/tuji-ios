// Routes pushed onto the MainTabsView NavigationStack. Adding a new
// destination = adding a case here + a switch arm in MainTabsView's
// .navigationDestination block.

import Foundation

enum NavRoute: Hashable {
    case cards
    case today
    case search
    case favorites
    case studyLanding(mode: StudyMode)
    case wordDetail(id: String)
    case categoryDetail(id: String)
}
