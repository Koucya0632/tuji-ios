// Routes pushed onto the MainTabsView NavigationStack. Adding a new
// destination = adding a case here + a switch arm in MainTabsView's
// .navigationDestination block.

import Foundation

enum NavRoute: Hashable {
    case cards
    case today
    case wordDetail(id: String)
    case categoryDetail(id: String)
}
