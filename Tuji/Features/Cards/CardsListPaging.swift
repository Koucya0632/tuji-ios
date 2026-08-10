// The 圖鑑 list's filter + page window.
//
// Both used to be `private var`s on `CardsListView`, computed inside `body`
// against `@State visibleCount` — so neither the source filter nor the
// "is there another page" rule could be tested, and the two had to be read
// together to know what the grid would actually show.
//
// A value rather than a view model: there is nothing async here, and keeping it
// a pure derivation means a test can hand it words and get the answer.

import Foundation

struct CardsListPage: Equatable {
    /// What the grid renders.
    let words: [CardWord]
    /// Whether 顯示更多 has anything left to reveal.
    let canShowMore: Bool
    /// How many words matched the filter, before the page window.
    let matchCount: Int
}

enum CardsListPaging {
    /// One screenful. Deliberately large: the grid is dense and a small page
    /// makes 顯示更多 feel like the list is fighting back.
    static let pageSize = 60

    /// `source == nil` means "everything" — reachable by tapping the lit chip,
    /// and distinct from a source that happens to match nothing.
    static func page(
        words: [CardWord],
        source: CardsSource?,
        isBookmarked: (String) -> Bool,
        visibleCount: Int
    )
        -> CardsListPage
    {
        let matched = source.map { source in
            words.filter { source.matches($0, isBookmarked: isBookmarked) }
        } ?? words
        return CardsListPage(
            words: Array(matched.prefix(max(0, visibleCount))),
            canShowMore: visibleCount < matched.count,
            matchCount: matched.count
        )
    }
}
