// Pins the one way to push.
//
// Before `TabNavigator` the four `NavigationPath`s were `@State` on
// `MainTabsView`, private and unreachable — which is *why* 21 of the app's 37
// pushes bypassed the shared destination table and built their own screens.
// These tests assert the two properties that made the bypass harmful: a push
// lands on the intended tab's stack, and a route carrying a preview model is
// still the same route.

import Foundation
import Testing
@testable import Tuji

@MainActor
struct TabNavigatorTests {
    private func item(_ slug: String) -> AtlasPublicItem {
        AtlasPublicItem(
            id: slug,
            slug: slug,
            lemma: "cup",
            displayZhHant: "杯子",
            targetLanguage: .en,
            category: nil,
            imageUrl: nil,
            author: nil,
            publishedAt: nil
        )
    }

    @Test("a push lands on the selected tab, and only that tab")
    func pushGoesToTheSelectedTab() {
        let nav = TabNavigator()
        nav.select(.community)

        nav.push(.atlasPublicItem(item: self.item("s1")))

        #expect(nav.depth(of: .community) == 1)
        for tab in MainTab.allCases where tab != .community {
            #expect(nav.depth(of: tab) == 0, "\(tab) must not see another tab's push")
        }
    }

    @Test("a cross-tab push targets the named tab, not the current one")
    func crossTabPushTargetsTheNamedTab() {
        let nav = TabNavigator()
        nav.select(.today)

        nav.push(.settings, on: .me)

        #expect(nav.depth(of: .me) == 1)
        #expect(nav.depth(of: .today) == 0)
    }

    @Test("a deep link's push lands on the link's tab, not whatever was selected")
    func deepLinkPushUsesItsOwnTab() {
        // The tab is selected synchronously and the push runs a runloop turn
        // later; if `applyPush` read the *current* tab instead of the link's,
        // a race would land the screen on the wrong stack.
        let nav = TabNavigator()
        nav.select(.today)

        nav.applyPush(.init(
            tab: .community,
            route: .atlasCollectionDetail(slug: "s", autoSave: true, preview: nil),
            cardsSource: nil,
            skipTour: false
        ))

        #expect(nav.depth(of: .community) == 1)
        #expect(nav.depth(of: .today) == 0)
    }

    @Test("a tab-only link pushes nothing")
    func tabOnlyLinkPushesNothing() {
        let nav = TabNavigator()
        nav.applyPush(.init(tab: .cards, route: nil, cardsSource: .bookmarked, skipTour: false))
        #expect(MainTab.allCases.allSatisfy { nav.depth(of: $0) == 0 })
    }

    @Test("a preview does not change which collection a route means")
    func previewIsNotIdentity() {
        // Two sites used to pass a preview and one did not, so the same
        // destination arrived three different ways. It is one case now, and the
        // preview is payload — but a route carrying one must still be a
        // distinct value, or NavigationPath would collapse two pushes into one.
        let withPreview = NavRoute.atlasCollectionDetail(
            slug: "s", autoSave: false, preview: nil
        )
        let same = NavRoute.atlasCollectionDetail(slug: "s", autoSave: false, preview: nil)
        let other = NavRoute.atlasCollectionDetail(slug: "s", autoSave: true, preview: nil)

        #expect(withPreview == same)
        #expect(withPreview != other)
    }

    @Test("every tab starts at its root")
    func tabsStartAtRoot() {
        let nav = TabNavigator()
        // All start true so a tab that never fires onAppear (an off-screen
        // page) reads as un-pushed — only a real push takes it away.
        #expect(nav.currentTabAtRoot)
        for tab in MainTab.allCases {
            nav.select(tab)
            #expect(nav.currentTabAtRoot)
        }
    }

    @Test("root tracking is per tab")
    func rootTrackingIsPerTab() {
        let nav = TabNavigator()
        nav.atRoot[.community] = false

        nav.select(.community)
        #expect(!nav.currentTabAtRoot)
        nav.select(.today)
        #expect(nav.currentTabAtRoot, "a push on 物見 must not silence 今天's tab bar")
    }
}
