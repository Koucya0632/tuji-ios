import Testing
@testable import Tuji

struct CardsListThemeVisibilityTests {
    /// `custom` and `community` are sources, not themes. They used to be pinned
    /// into the theme row so they stayed reachable when empty; that job moved to
    /// the source row, which offers them unconditionally. Leaving them in both
    /// rows would show one filter twice under two different meanings.
    @Test
    func sourceCategoriesAreNotThemes() {
        let categories = [
            self.category(id: "custom", nameZh: "自定義"),
            self.category(id: "community", nameZh: "社群圖鑑"),
            self.category(id: "kitchen", nameZh: "廚房")
        ]

        let visible = CardsListView.visibleThemeCategories(
            from: categories,
            presentIds: ["kitchen", "custom", "community"]
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
        #expect(CardsSource.available(isGuest: true) == [.all, .official, .bookmarked])
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
