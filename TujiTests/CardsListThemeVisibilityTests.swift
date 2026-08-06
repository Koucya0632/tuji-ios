import Testing
@testable import Tuji

struct CardsListThemeVisibilityTests {
    /// `custom` and `community` are sources, not themes. They used to be pinned
    /// into 圖鑑's theme chip row so they stayed reachable with no cards in them;
    /// that job belongs to the source row, which offers them unconditionally.
    /// The theme row is gone entirely now and this rule moved to 主題, where it
    /// still has to hold: listing them there would present one filter twice
    /// under two different meanings.
    @Test
    func sourceCategoriesAreNotThemes() {
        let categories = [
            self.category(id: "custom", nameZh: "自定義"),
            self.category(id: "community", nameZh: "物見"),
            self.category(id: "kitchen", nameZh: "廚房")
        ]

        let visible = CategoryIndexView.visibleThemeCategories(
            from: categories,
            presentIds: ["kitchen", "custom", "community"]
        )

        #expect(visible.map(\.id) == ["kitchen"])
    }

    /// A theme with nothing behind it is a dead end, so it stays off the index.
    @Test
    func themesWithoutWordsAreHidden() {
        let categories = [
            self.category(id: "kitchen", nameZh: "廚房"),
            self.category(id: "zodiac", nameZh: "生肖")
        ]

        let visible = CategoryIndexView.visibleThemeCategories(
            from: categories,
            presentIds: ["kitchen"]
        )

        #expect(visible.map(\.id) == ["kitchen"])
    }

    /// The source row still offers every value with content behind it, so a user
    /// with no saved community words can still ask to see them and get a
    /// truthful empty result rather than a missing filter.
    @Test
    func sourceRowAlwaysOffersTakenAndMineWhenSignedIn() {
        #expect(CardsSource.available(isGuest: false) == CardsSource.allCases)
    }

    /// A guest has no account-scoped content, so two values could only ever say
    /// "nothing here" — worse than not offering them.
    @Test
    func guestsDoNotSeeAccountScopedSources() {
        #expect(CardsSource.available(isGuest: true) == [.official, .bookmarked])
    }

    /// There is no 全部 case: "everything" is the absence of a filter, which the
    /// grid spells `nil`. A case for it would have put a second 全部 chip on
    /// screen beside the theme row's, each meaning something different.
    @Test
    func thereIsNoAllCase() {
        #expect(CardsSource(rawValue: "all") == nil)
        #expect(CardsSource.allCases == [.official, .mine, .taken, .bookmarked])
    }

    private func category(id: String, nameZh: String) -> TujiCategory {
        TujiCategory(
            id: id,
            name: id,
            nameZh: nameZh,
            emoji: "",
            description: nil,
            color: nil,
            imageUrl: nil
        )
    }
}
