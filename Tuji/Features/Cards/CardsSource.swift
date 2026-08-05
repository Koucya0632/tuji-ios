// Which batch of words the 圖鑑 grid is showing.
//
// The grid used to have one filter row — categories, with 自製圖鑑 and 社群圖鑑
// sitting in it as if they were themes like "kitchen". They are not themes, they
// are *where a word came from*, and mixing the two axes into one row meant the
// user could never ask "show me only the ones I made, in the kitchen".
//
// Source is now its own row, and category is a second row that only applies to
// dictionary words — a word you photographed has no theme to filter by.

import SwiftUI

enum CardsSource: String, CaseIterable, Identifiable {
    case all
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
        case .all: "全部"
        case .official: "官方"
        case .mine: "我做的"
        case .taken: "已收進"
        case .bookmarked: "書籤"
        }
    }

    /// Categories only describe dictionary words, so the second row is hidden
    /// for the source values that cannot have one.
    var allowsCategoryFilter: Bool {
        switch self {
        case .all, .official: true
        case .mine, .taken, .bookmarked: false
        }
    }

    /// A guest has no account-scoped content, so two of the values would always
    /// come back empty. Offering a filter that can only ever say "nothing here"
    /// is worse than not offering it.
    static func available(isGuest: Bool) -> [CardsSource] {
        isGuest ? [.all, .official, .bookmarked] : allCases
    }

    func matches(_ word: CardWord, isBookmarked: (String) -> Bool) -> Bool {
        switch self {
        case .all: true
        case .official: word.category != "custom" && word.category != "community"
        case .mine: word.category == "custom"
        case .taken: word.category == "community"
        case .bookmarked: isBookmarked(word.id)
        }
    }
}
