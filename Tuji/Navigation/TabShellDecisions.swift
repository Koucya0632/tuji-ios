// The tab shell's three policies, as pure functions.
//
// `MainTabsView` is the app's navigation root and had **no tests at all** — its
// tab selection, its four `NavigationPath`s, `atRoot`, and `consumePendingLink`
// are `private` state on a `View`, so nothing could assert that tapping a link
// lands anywhere in particular. That matters more here than on a normal screen,
// because two of these policies exist *because they were already wrong once*:
//
//   - the swipe guard read `NavigationPath.count`, which sees only value-based
//     pushes. A 物見 collection card pushes via `navigationDestination(item:)`,
//     so the count stayed 0 and the horizontal pager stayed live on top of the
//     pushed detail, racing NavigationStack's own edge-swipe-to-pop.
//   - a guest tapping a shared 合集 link has to survive the root swap to
//     Welcome and the whole sign-in flow, so the intent must be *held*, not
//     consumed, while signed out.
//
// This module changes none of that. It only moves the decisions somewhere a
// test can reach them, so the seam work that follows has a net under it.

import Foundation

/// What the shell should do about a pending deep link.
enum PendingLinkEffect: Equatable {
    /// Leave it pending. The only case: a guest's auto-save collection intent,
    /// which the signed-in shell consumes after sign-in completes.
    case hold
    /// Nothing pending.
    case none
    case apply(Applied)

    struct Applied: Equatable {
        var tab: MainTab
        var route: NavRoute?
        /// Set only by `tuji://favorites`, which selects a *source filter* on
        /// 圖鑑 rather than opening a screen — 我的收藏 stopped being a screen.
        var cardsSource: CardsSource?
        /// A deep link (e.g. a push-notification tap) outranks the first-run tour.
        var skipTour: Bool
    }
}

enum TabShellDecisions {
    static func pendingLinkEffect(
        pending: TujiDeepLink?,
        isSignedIn: Bool,
        tourActive: Bool
    )
        -> PendingLinkEffect
    {
        guard let pending else { return .none }
        if case let .collection(_, autoSave) = pending, autoSave, !isSignedIn {
            return .hold
        }
        var cardsSource: CardsSource?
        if case .favorites = pending { cardsSource = .bookmarked }
        return .apply(
            .init(
                tab: pending.tab,
                route: pending.route,
                cardsSource: cardsSource,
                skipTour: tourActive
            )
        )
    }

    /// The floating bar steps aside for a focused study session, and for
    /// anything opened from 我 or 物見: both tabs are hubs of entry points, and
    /// a screen opened from one owns the window until the user comes back.
    ///
    /// 今天 and 圖鑑 keep their bar through a push, because a word detail is a
    /// place you come back from, not a window you are handed.
    static func tabBarVisible(
        selected: MainTab,
        currentTabAtRoot: Bool,
        studyFocusActive: Bool
    )
        -> Bool
    {
        if studyFocusActive { return false }
        switch selected {
        case .me, .community: return currentTabAtRoot
        case .today, .cards: return true
        }
    }

    /// The pager's horizontal swipe. Same signal as the bar, different policy:
    /// a pushed screen disables the swipe on *every* tab, because the race it
    /// causes is with NavigationStack's edge-swipe-to-pop, which exists
    /// everywhere.
    static func swipeEnabled(currentTabAtRoot: Bool, studyFocusActive: Bool) -> Bool {
        !studyFocusActive && currentTabAtRoot
    }
}
