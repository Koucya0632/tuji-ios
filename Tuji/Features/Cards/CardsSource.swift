// Which batch of words the 圖鑑 grid is showing.
//
// The grid used to have one filter row — categories, with 自製圖鑑 and 物見
// sitting in it as if they were themes like "kitchen". They are not themes, they
// are *where a word came from*, and mixing the two axes into one row meant the
// user could never ask "show me only the ones I made".
//
// Source is now the only row here. Theme moved out of 圖鑑 entirely — a
// horizontal strip of chips cannot survive a catalogue of forty themes, and a
// theme already has a page of its own (CategoryView). Browsing by theme is
// CategoryIndexView's job.
//
// There is no `全部` case. "All" is the *absence* of a filter, not a filter, and
// spelling it as a chip meant two rows each opened with a 全部 that meant
// something different. Tapping the selected chip again clears it, and `nil` is
// that unfiltered state — reachable, but not where the tab opens. 圖鑑 opens on
// `official`, because the dictionary is what the tab is for.

import SwiftUI

enum CardsSource: String, CaseIterable, Identifiable {
    /// The published dictionary.
    case official
    /// 自製圖鑑 — words the user photographed.
    case mine
    /// Words taken in from someone else's atlas (收進圖鑑).
    case taken
    /// 書籤 — dictionary words the user marked to look at again. Passive: this
    /// never changes what is scheduled for review.
    case bookmarked

    var id: String {
        self.rawValue
    }

    var title: LocalizedStringKey {
        switch self {
        case .official: "官方"
        case .mine: "我做的"
        case .taken: "已收進"
        case .bookmarked: "書籤"
        }
    }

    /// A guest has no account-scoped content, so two of the values would always
    /// come back empty. Offering a filter that can only ever say "nothing here"
    /// is worse than not offering it.
    static func available(isGuest: Bool) -> [CardsSource] {
        isGuest ? [.official, .bookmarked] : allCases
    }

    func matches(_ word: CardWord, isBookmarked: (String) -> Bool) -> Bool {
        switch self {
        case .official: word.category != "custom" && word.category != "community"
        case .mine: word.category == "custom"
        case .taken: word.category == "community"
        case .bookmarked: isBookmarked(word.id)
        }
    }
}
