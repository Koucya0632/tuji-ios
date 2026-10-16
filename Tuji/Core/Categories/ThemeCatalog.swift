// Which rows of the categories table are *themes*.
//
// The rule used to be a static on 主題's own view, which was fine while that
// screen was the only place a list of themes was drawn. 圖鑑·官方 is now the
// theme shelf and that screen is gone, so the rule lives under the name of what
// it decides rather than the name of who first asked.

import Foundation

enum ThemeCatalog {
    /// Themes only, and only ones with words behind them. `custom` and
    /// `community` are rows in the categories table but they are *sources* —
    /// where a word came from — not themes, and they have their own filter on
    /// 圖鑑. Listing them here would present one filter twice under two
    /// different meanings.
    ///
    /// - Parameters:
    ///   - categories: the catalogue, in server order.
    ///   - presentIds: the category ids the loaded dictionary actually has
    ///     words for.
    static func themes(
        from categories: [TujiCategory],
        presentIds: Set<String>
    )
        -> [TujiCategory]
    {
        categories.filter {
            self.isTheme($0.id) && presentIds.contains($0.id)
        }
    }

    /// 自製 and 物見 are categories in the catalogue but not themes.
    static func isTheme(_ categoryId: String) -> Bool {
        categoryId != "custom" && categoryId != "community"
    }
}
