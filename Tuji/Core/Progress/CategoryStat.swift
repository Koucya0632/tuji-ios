// One theme's row in 我的進度's breakdown, and the join that produces the list.
//
// It was 28 lines in a `private var` on `MeProgressSections`, reading three
// `@Environment` stores: scope to the selection, drop themes with no words
// behind them, index by id, then join against the catalogue's order — with a
// fallback that renders raw category ids as names when the catalogue has not
// loaded. Nothing could reach any of it.
//
// The order is the join's whole point: the rows follow the catalogue's order,
// not whatever order the progress endpoint answered in, so the list does not
// reshuffle itself between loads.

import Foundation

struct CategoryStat: Identifiable, Equatable {
    let id: String
    let nameZh: String
    let learned: Int
    let total: Int

    var ratio: Double {
        CompletionReadout.ratio(seen: self.learned, total: self.total)
    }
}

extension CategoryStat {
    /// The breakdown rows, in catalogue order.
    ///
    /// - `selected` empty means "no themes picked", which shows everything
    ///   rather than nothing — the same reading 完成度 gives an empty selection.
    /// - A theme with `total == 0` has no words behind it and is dropped: a row
    ///   reading 0/0 is not progress, it is noise.
    /// - `categoryOrder` empty is the cold-open case: the catalogue has not
    ///   arrived, so the rows fall back to their raw ids as names. Ugly, and
    ///   deliberately so — it is visibly a loading artefact rather than a theme
    ///   whose name is missing.
    static func breakdown(
        progress: [CategoryProgress],
        selected: [String],
        categoryOrder: [TujiCategory]
    )
        -> [CategoryStat]
    {
        let scoped = selected.isEmpty
            ? progress
            : progress.filter { selected.contains($0.category) }
        let withWords = scoped.filter { $0.total > 0 }
        guard !withWords.isEmpty else { return [] }

        let byId = Dictionary(withWords.map { ($0.category, $0) }, uniquingKeysWith: { first, _ in first })
        guard !categoryOrder.isEmpty else {
            return withWords.map {
                CategoryStat(id: $0.category, nameZh: $0.category, learned: $0.seen, total: $0.total)
            }
        }
        return categoryOrder.compactMap { category in
            guard let row = byId[category.id] else { return nil }
            return CategoryStat(
                id: category.id,
                nameZh: category.nameZh,
                learned: row.seen,
                total: row.total
            )
        }
    }
}
