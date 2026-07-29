// Pins how saved 社群圖鑑 items reach the 圖鑑 page.
//
// They arrive already shaped as words under `category: "community"`, so the
// theme chip, the list, the mastery badges and search all work through the
// paths that already existed — no second list implementation. What makes them
// different is where a tap goes: these belong to someone else, so they open on
// the public detail (author / 取消收藏 / 檢舉), and the `saved:` id prefix is
// what carries that decision.

import Testing
@testable import Tuji

struct SavedCommunityWordsTests {
    private func word(_ id: String, category: String) -> CardWord {
        CardWord(
            id: id,
            word: "kettle",
            chinese: "水壺",
            imageUrl: "",
            category: category,
            pronunciation: ""
        )
    }

    // MARK: - Routing

    @Test
    func savedIdsCarryTheirSlug() {
        #expect("saved:kettle-3c0d274b".savedCommunitySlug == "kettle-3c0d274b")
    }

    /// Everything else must keep going to the word screen. `atlas:` in
    /// particular resolves through the OWNER-scoped detail endpoint, which would
    /// 404 for someone else's item.
    @Test
    func onlySavedIdsRouteToThePublicDetail() {
        #expect("atlas:9f8e7d6c".savedCommunitySlug == nil)
        #expect("kettle".savedCommunitySlug == nil)
        #expect("unsaved:x".savedCommunitySlug == nil)
        #expect("".savedCommunitySlug == nil)
        // A prefix with nothing after it is not a destination.
        #expect("saved:".savedCommunitySlug == nil)
    }

    // MARK: - Merge

    @Test
    func savedWordsJoinTheStoreUnderTheirOwnTheme() {
        let merged = WordsStore.merge(
            publicWords: [self.word("w1", category: "kitchen")],
            customWords: [self.word("saved:s1", category: "community")]
        )
        #expect(merged.count == 2)
        #expect(merged.contains { $0.category == "community" })
    }

    /// The atlas page derives its chips from the categories present in the
    /// store, so a user who has saved nothing simply has no 社群圖鑑 chip —
    /// which is the whole reason the theme is opt-in for new cards too.
    @Test
    func noSavedItemsMeansNoCommunityCategory() {
        let merged = WordsStore.merge(
            publicWords: [self.word("w1", category: "kitchen")],
            customWords: []
        )
        #expect(merged.contains { $0.category == "community" } == false)
    }

    /// Saved and custom items are separate sources merged in sequence; an id
    /// collision between them would be a server bug, but it must not trap.
    @Test
    func mergingIsLastWinsAcrossBothPersonalSources() {
        let first = WordsStore.merge(
            publicWords: [self.word("w1", category: "kitchen")],
            customWords: [self.word("atlas:a1", category: "custom")]
        )
        let second = WordsStore.merge(
            publicWords: first,
            customWords: [self.word("saved:s1", category: "community")]
        )
        #expect(second.count == 3)
        #expect(Set(second.map(\.category)) == ["kitchen", "custom", "community"])
    }
}
