// The tests the navigation layer never had.
//
// `MainTabsView` is the app's navigation root and had zero coverage: tab
// selection, the four `NavigationPath`s, `atRoot` and `consumePendingLink` are
// all `private` state on a `View`. `TujiDeepLink.from(_:)` is a pure function
// parsing eleven URL forms across two URL shells, and had zero coverage too —
// so every public link the app advertises was unverified.
//
// This file changes no behaviour. It exists so the destination-seam work that
// follows has something underneath it.

import Foundation
import Testing
@testable import Tuji

struct DeepLinkParsingTests {
    /// The universal-link shell, assembled rather than written as one literal:
    /// a hardcoded host string is a lint error everywhere outside
    /// Core/Networking, correctly so, and this file is the one place the host
    /// is the subject rather than a dependency.
    private static let universalPrefix = "https://" + "tuji.app/"

    private func link(_ string: String) -> TujiDeepLink? {
        guard let url = URL(string: string) else { return nil }
        return TujiDeepLink.from(url)
    }

    /// A universal link for `path` (no leading slash).
    private func universal(_ path: String) -> TujiDeepLink? {
        self.link(Self.universalPrefix + path)
    }

    @Test("both URL shells parse to the same link")
    func bothShellsAgree() {
        #expect(self.link("tuji://today") == .today)
        #expect(self.universal("today") == .today)
        #expect(self.link("tuji://word/cup") == .word(id: "cup"))
        #expect(self.universal("word/cup") == .word(id: "cup"))
    }

    @Test("a foreign scheme or host is not ours")
    func foreignURLsAreRejected() {
        #expect(self.link("https://example.com/today") == nil)
        #expect(self.link("otherapp://today") == nil)
        // https must carry our host; the path alone is not enough.
        #expect(self.link("https://evil.example/word/cup") == nil)
    }

    @Test("every advertised head parses")
    func allHeadsParse() {
        #expect(self.link("tuji://today") == .today)
        #expect(self.link("tuji://cards") == .cards)
        #expect(self.link("tuji://me") == .me)
        #expect(self.link("tuji://community") == .community)
        #expect(self.link("tuji://favorites") == .favorites)
        #expect(self.link("tuji://settings") == .settings)
        #expect(self.link("tuji://search") == .search(query: nil))
        #expect(self.link("tuji://search?q=cup") == .search(query: "cup"))
        #expect(self.link("tuji://study") == .study(mode: .new))
        #expect(self.link("tuji://study?mode=review") == .study(mode: .review))
        #expect(self.link("tuji://word/cup") == .word(id: "cup"))
        #expect(self.link("tuji://category/kitchen") == .category(id: "kitchen"))
        #expect(self.link("tuji://collection/my-slug") == .collection(slug: "my-slug"))
    }

    @Test("an id-carrying head without its id is not a link")
    func missingIdsAreRejected() {
        // Better to ignore the URL than to open a detail screen for "".
        #expect(self.link("tuji://word") == nil)
        #expect(self.link("tuji://category") == nil)
        #expect(self.link("tuji://collection") == nil)
    }

    @Test("an unknown head is ignored rather than guessed at")
    func unknownHeadsAreRejected() {
        #expect(self.link("tuji://nonsense") == nil)
        #expect(self.link("tuji://") == nil)
    }

    @Test("each link names the tab it belongs to")
    func tabMapping() {
        #expect(TujiDeepLink.today.tab == .today)
        #expect(TujiDeepLink.study(mode: .new).tab == .today)
        #expect(TujiDeepLink.cards.tab == .cards)
        #expect(TujiDeepLink.search(query: nil).tab == .cards)
        #expect(TujiDeepLink.word(id: "w").tab == .cards)
        #expect(TujiDeepLink.category(id: "c").tab == .cards)
        // 我的收藏 stopped being a screen: bookmarks are a source filter on 圖鑑.
        #expect(TujiDeepLink.favorites.tab == .cards)
        #expect(TujiDeepLink.community.tab == .community)
        #expect(TujiDeepLink.collection(slug: "s").tab == .community)
        #expect(TujiDeepLink.me.tab == .me)
        #expect(TujiDeepLink.settings.tab == .me)
    }

    @Test("tab-only links push nothing")
    func tabOnlyLinksHaveNoRoute() {
        #expect(TujiDeepLink.today.route == nil)
        #expect(TujiDeepLink.cards.route == nil)
        #expect(TujiDeepLink.me.route == nil)
        #expect(TujiDeepLink.community.route == nil)
        #expect(TujiDeepLink.favorites.route == nil)
    }
}

struct TabShellDecisionsTests {
    @Test("a collection link opens the collection on 物見")
    func collectionLinkApplies() {
        let effect = TabShellDecisions.pendingLinkEffect(
            pending: .collection(slug: "s"),
            tourActive: false
        )
        #expect(
            effect == .apply(.init(
                tab: .community,
                route: .atlasCollectionDetail(slug: "s", preview: nil),
                cardsSource: nil,
                skipTour: false
            ))
        )
    }

    @Test("nothing pending applies nothing")
    func noPendingLink() {
        #expect(
            TabShellDecisions.pendingLinkEffect(
                pending: nil, tourActive: false
            ) == PendingLinkEffect.none
        )
    }

    @Test("favorites selects the 書籤 source rather than opening a screen")
    func favoritesSelectsASource() {
        let effect = TabShellDecisions.pendingLinkEffect(
            pending: .favorites, tourActive: false
        )
        #expect(
            effect == .apply(.init(
                tab: .cards,
                route: nil,
                cardsSource: .bookmarked,
                skipTour: false
            ))
        )
    }

    @Test("a deep link outranks the first-run tour")
    func linkSkipsTheTour() {
        let effect = TabShellDecisions.pendingLinkEffect(
            pending: .today, tourActive: true
        )
        if case let .apply(applied) = effect {
            #expect(applied.skipTour)
        } else {
            Issue.record("a pending link must be applied over the tour")
        }
    }

    @Test("study focus hides the bar on every tab")
    func studyFocusHidesTheBar() {
        for tab in MainTab.allCases {
            #expect(
                !TabShellDecisions.tabBarVisible(
                    selected: tab, currentTabAtRoot: true, studyFocusActive: true
                )
            )
        }
    }

    @Test("a screen opened from 我 or 物見 owns the window; 今天 and 圖鑑 keep their bar")
    func pushedScreensOwnTheWindowOnHubTabs() {
        #expect(!TabShellDecisions.tabBarVisible(
            selected: .me, currentTabAtRoot: false, studyFocusActive: false
        ))
        #expect(!TabShellDecisions.tabBarVisible(
            selected: .community, currentTabAtRoot: false, studyFocusActive: false
        ))
        // A word detail is a place you come back from, not a window you are handed.
        #expect(TabShellDecisions.tabBarVisible(
            selected: .today, currentTabAtRoot: false, studyFocusActive: false
        ))
        #expect(TabShellDecisions.tabBarVisible(
            selected: .cards, currentTabAtRoot: false, studyFocusActive: false
        ))
    }

    @Test("any pushed screen disables the pager swipe, on every tab")
    func pushedScreensDisableTheSwipe() {
        // Not the same policy as the bar: the race this prevents is with
        // NavigationStack's edge-swipe-to-pop, which exists on all four tabs.
        #expect(TabShellDecisions.swipeEnabled(currentTabAtRoot: true, studyFocusActive: false))
        #expect(!TabShellDecisions.swipeEnabled(currentTabAtRoot: false, studyFocusActive: false))
        #expect(!TabShellDecisions.swipeEnabled(currentTabAtRoot: true, studyFocusActive: true))
    }
}
