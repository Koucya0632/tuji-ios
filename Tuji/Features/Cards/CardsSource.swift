// Which batch of words the 圖鑑 grid is showing.
//
// The grid used to have one filter row — categories, with 自製圖鑑 and 物見
// sitting in it as if they were themes like "kitchen". They are not themes, they
// are *where a word came from*, and mixing the two axes into one row meant the
// user could never ask "show me only the ones I made".
//
// Source is now the only row here. Theme is not a second row either — a
// horizontal strip of chips cannot survive a catalogue of forty themes — it is
// what 官方 *is*: that source shows the shelf of themes, and the words behind a
// theme are on the theme's own page (CategoryView).
//
// There is no `全部` case, and no unfiltered state either. "All" used to be
// reachable by tapping the lit chip a second time to clear it — a state with no
// chip to show it was on, which is indistinguishable from "the row is broken".
// A filter row that can end up looking unselected teaches the user to distrust
// it, and mixing four sources into one grid answers a question nobody asked:
// 官方 and 我做的 are different *kinds* of thing, not two halves of a list.
//
// So one source is always in effect. Tapping the lit chip does nothing; 圖鑑
// opens on `official`, because the dictionary is what the tab is for.

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

    /// 官方 draws themes; every other source draws words.
    ///
    /// The official half of the catalogue is the only one that *has* themes —
    /// a word you photographed or took in from 物見 belongs to no theme — and
    /// at 757 words a flat grid behind a 顯示更多 button was a list you paged
    /// through rather than a shelf you browsed. Named here rather than left as
    /// an `if` in the view so the two layouts are one decision with a test.
    var showsThemes: Bool {
        self == .official
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
