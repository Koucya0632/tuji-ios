// Pins the 圖鑑 grid's filter + page window.
//
// Both lived as `private var`s on `CardsListView`, computed inside `body`
// against `@State visibleCount`, so neither could be reached by a test — and
// they have to agree: `canShowMore` is about the *filtered* list, not the whole
// dictionary, or 顯示更多 appears on a filter that has nothing more to show.

import Testing
@testable import Tuji

struct CardsListPagingTests {
    private func word(_ id: String, category: String) -> CardWord {
        CardWord(
            id: id,
            word: id,
            chinese: id,
            imageUrl: "",
            category: category,
            pronunciation: ""
        )
    }

    private var corpus: [CardWord] {
        [
            self.word("a", category: "kitchen"),
            self.word("b", category: "custom"),
            self.word("c", category: "community"),
            self.word("d", category: "kitchen")
        ]
    }

    private func never(_: String) -> Bool {
        false
    }

    @Test("no source means no filter, not an empty list")
    func nilSourceShowsEverything() {
        let page = CardsListPaging.page(
            words: self.corpus, source: nil, isBookmarked: self.never, visibleCount: 60
        )
        #expect(page.matchCount == 4)
        #expect(!page.canShowMore)
    }

    @Test("官方 excludes both 自製圖鑑 and 物見")
    func officialExcludesUserSources() {
        let page = CardsListPaging.page(
            words: self.corpus, source: .official, isBookmarked: self.never, visibleCount: 60
        )
        #expect(page.words.map(\.id) == ["a", "d"])
    }

    @Test("自製圖鑑 and 物見 are different sources, not one 'mine'")
    func customAndCommunityAreDistinct() {
        let mine = CardsListPaging.page(
            words: self.corpus, source: .mine, isBookmarked: self.never, visibleCount: 60
        )
        let taken = CardsListPaging.page(
            words: self.corpus, source: .taken, isBookmarked: self.never, visibleCount: 60
        )
        #expect(mine.words.map(\.id) == ["b"])
        #expect(taken.words.map(\.id) == ["c"])
    }

    @Test("書籤 asks the predicate, not the category")
    func bookmarkedUsesThePredicate() {
        let page = CardsListPaging.page(
            words: self.corpus,
            source: .bookmarked,
            isBookmarked: { $0 == "c" || $0 == "d" },
            visibleCount: 60
        )
        #expect(page.words.map(\.id) == ["c", "d"])
    }

    @Test("顯示更多 tracks the filtered list, not the whole dictionary")
    func canShowMoreIsScopedToTheFilter() {
        // The trap: a corpus longer than one page, filtered down to less than
        // one page. 顯示更多 must not appear.
        let many = (0..<100).map { self.word("k\($0)", category: "kitchen") }
            + [self.word("only", category: "custom")]
        let filtered = CardsListPaging.page(
            words: many, source: .mine, isBookmarked: self.never, visibleCount: 60
        )
        #expect(filtered.matchCount == 1)
        #expect(!filtered.canShowMore)

        let unfiltered = CardsListPaging.page(
            words: many, source: nil, isBookmarked: self.never, visibleCount: 60
        )
        #expect(unfiltered.canShowMore)
        #expect(unfiltered.words.count == 60)
    }

    @Test("revealing the last page turns 顯示更多 off")
    func lastPageEndsPaging() {
        let many = (0..<70).map { self.word("k\($0)", category: "kitchen") }
        let second = CardsListPaging.page(
            words: many, source: nil, isBookmarked: self.never, visibleCount: 120
        )
        #expect(second.words.count == 70)
        #expect(!second.canShowMore)
    }
}
