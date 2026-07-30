import Testing
@testable import Tuji

struct CardsListThemeVisibilityTests {
    @Test
    func communityThemeRemainsVisibleWithoutSavedCards() {
        let categories = [
            self.category(id: "custom", nameZh: "自定義"),
            self.category(id: "community", nameZh: "社群圖鑑"),
            self.category(id: "kitchen", nameZh: "廚房")
        ]

        let visible = CardsListView.visibleThemeCategories(
            from: categories,
            presentIds: ["kitchen"]
        )

        #expect(visible.map(\.id) == ["custom", "community", "kitchen"])
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
