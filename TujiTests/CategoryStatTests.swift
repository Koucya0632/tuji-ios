// Pins 我的進度's theme breakdown.
//
// It was 28 lines in a `private var` on `MeProgressSections`, reading three
// `@Environment` stores — the scope-to-selection, the drop-empty-themes filter,
// the id index, the catalogue-order join, and a fallback that renders raw
// category ids as names. Nothing could reach any of it.

import Foundation
import Testing
@testable import Tuji

struct CategoryStatTests {
    private func progress(_ pairs: [(String, seen: Int, total: Int)]) -> [CategoryProgress] {
        pairs.map { CategoryProgress(category: $0.0, total: $0.total, seen: $0.seen) }
    }

    private func catalogue(_ ids: [String]) -> [TujiCategory] {
        ids.map {
            TujiCategory(
                id: $0,
                name: $0,
                nameZh: "名-\($0)",
                emoji: "",
                description: nil,
                color: nil,
                imageUrl: nil
            )
        }
    }

    /// The join's whole point: rows follow the catalogue's order, not whatever
    /// order the progress endpoint answered in, so the list does not reshuffle
    /// itself between loads.
    @Test
    func rowsFollowTheCatalogueOrderNotTheResponseOrder() {
        let rows = CategoryStat.breakdown(
            progress: self.progress([("street", seen: 1, total: 10), ("kitchen", seen: 2, total: 20)]),
            selected: [],
            categoryOrder: self.catalogue(["kitchen", "street"])
        )
        #expect(rows.map(\.id) == ["kitchen", "street"])
        #expect(rows.map(\.nameZh) == ["名-kitchen", "名-street"])
    }

    /// A theme with no words behind it is not progress, it is noise.
    @Test
    func aThemeWithNoWordsIsDropped() {
        let rows = CategoryStat.breakdown(
            progress: self.progress([("kitchen", seen: 0, total: 0), ("street", seen: 1, total: 4)]),
            selected: [],
            categoryOrder: self.catalogue(["kitchen", "street"])
        )
        #expect(rows.map(\.id) == ["street"])
    }

    /// No themes picked shows everything — the same reading 完成度 gives an
    /// empty selection, rather than an empty screen.
    @Test
    func anEmptySelectionShowsEverything() {
        let rows = CategoryStat.breakdown(
            progress: self.progress([("kitchen", seen: 2, total: 20), ("street", seen: 1, total: 10)]),
            selected: [],
            categoryOrder: self.catalogue(["kitchen", "street"])
        )
        #expect(rows.count == 2)
    }

    @Test
    func aSelectionScopesTheRows() {
        let rows = CategoryStat.breakdown(
            progress: self.progress([("kitchen", seen: 2, total: 20), ("street", seen: 1, total: 10)]),
            selected: ["street"],
            categoryOrder: self.catalogue(["kitchen", "street"])
        )
        #expect(rows.map(\.id) == ["street"])
    }

    /// The cold-open case: the catalogue has not arrived, so rows fall back to
    /// their raw ids as names rather than vanishing. A user who opens 我 first
    /// still sees their numbers.
    @Test
    func anEmptyCatalogueFallsBackToRawIdsRatherThanNoRows() {
        let rows = CategoryStat.breakdown(
            progress: self.progress([("kitchen", seen: 2, total: 20)]),
            selected: [],
            categoryOrder: []
        )
        #expect(rows.map(\.id) == ["kitchen"])
        #expect(rows.map(\.nameZh) == ["kitchen"])
    }

    /// A theme the catalogue knows but the user has no progress rows for does
    /// not appear — the join is an inner one.
    @Test
    func aCatalogueThemeWithoutProgressIsNotInvented() {
        let rows = CategoryStat.breakdown(
            progress: self.progress([("kitchen", seen: 2, total: 20)]),
            selected: [],
            categoryOrder: self.catalogue(["kitchen", "bedroom"])
        )
        #expect(rows.map(\.id) == ["kitchen"])
    }

    @Test
    func nothingToShowIsAnEmptyList() {
        #expect(CategoryStat.breakdown(
            progress: [],
            selected: [],
            categoryOrder: self.catalogue(["kitchen"])
        ).isEmpty)
        #expect(CategoryStat.breakdown(
            progress: self.progress([("kitchen", seen: 2, total: 20)]),
            selected: ["street"],
            categoryOrder: self.catalogue(["kitchen"])
        ).isEmpty)
    }

    @Test
    func theRatioIsTheSharedOne() {
        let rows = CategoryStat.breakdown(
            progress: self.progress([("kitchen", seen: 5, total: 20)]),
            selected: [],
            categoryOrder: self.catalogue(["kitchen"])
        )
        #expect(rows.first?.ratio == CompletionReadout.ratio(seen: 5, total: 20))
    }
}
