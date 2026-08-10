// Where the tab shell's navigation state lives, and the one way to push.
//
// The four `NavigationPath`s used to be `@State` on `MainTabsView`, private and
// unreachable. That is *why* 21 of the app's 37 pushes bypassed the shared
// destination table: a feature screen with no access to a path had no way to
// push a route value, so it reached for `navigationDestination(item:)` and
// built the destination itself. The table's own comment claimed it kept "every
// entry point on the same destination" — it could not, and the two bugs below
// are what that cost.
//
// With the paths here and the navigator in the environment, a screen pushes a
// *route* and the table decides what that means. Routes carry models where the
// destination needs preview data (`AtlasPublicItem`, `AtlasCollection` are both
// `Hashable`), which is the capability `navigationDestination(item:)` was being
// reached for.

import Observation
import SwiftUI

@MainActor
@Observable
final class TabNavigator {
    var selected: MainTab = .today

    /// One path per tab, so a cross-tab push never disturbs the others.
    var todayPath = NavigationPath()
    var cardsPath = NavigationPath()
    var communityPath = NavigationPath()
    var mePath = NavigationPath()

    /// Whether each tab shows its own root rather than something pushed over
    /// it. All start true so a tab that never fires `onAppear` (an off-screen
    /// page) reads as un-pushed — only a real push takes it away.
    ///
    /// This is the *one* signal for "is something on top of this tab". There
    /// used to be two: this, and `NavigationPath.count`. They answered
    /// differently, and the wrong one drove the pager (see
    /// `TabShellDecisions.swipeEnabled`).
    var atRoot: [MainTab: Bool] = [:]

    /// A source the navigation layer wants shown (a `tuji://favorites` link).
    /// Consumed once and cleared, so it never fights a later manual pick.
    var cardsSourceRequest: CardsSource?

    var currentTabAtRoot: Bool {
        self.atRoot[self.selected] ?? true
    }

    func select(_ tab: MainTab) {
        self.selected = tab
    }

    /// Push onto the currently selected tab. The overwhelmingly common case: a
    /// screen pushes over itself.
    func push(_ route: NavRoute) {
        self.push(route, on: self.selected)
    }

    func push(_ route: NavRoute, on tab: MainTab) {
        switch tab {
        case .today: self.todayPath.append(route)
        case .cards: self.cardsPath.append(route)
        case .community: self.communityPath.append(route)
        case .me: self.mePath.append(route)
        }
    }

    func depth(of tab: MainTab) -> Int {
        switch tab {
        case .today: self.todayPath.count
        case .cards: self.cardsPath.count
        case .community: self.communityPath.count
        case .me: self.mePath.count
        }
    }

    /// The deep-link path's second half. The tab and the source filter are
    /// applied synchronously; this runs a runloop turn later, once the newly
    /// selected tab's NavigationStack has mounted.
    func applyPush(_ applied: PendingLinkEffect.Applied) {
        guard let route = applied.route else { return }
        self.push(route, on: applied.tab)
    }
}
