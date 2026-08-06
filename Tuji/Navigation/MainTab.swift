// The four primary tabs surfaced in MainTabsView.
//
// The semantic axis is 時間 → 內容 → 他人 → 自己: what to do today, all the
// words, other people's words, what you have accumulated. 進度 used to sit
// between 圖鑑 and 物見 and broke that line — it was not a *place*, it was a
// readout about you, which is what 我 is for. Its content moved there whole.
//
// **UI name vs domain name.** The third tab is 物見 on screen; in code and in
// the domain vocabulary it stays `community` / 公開圖鑑. That is deliberate, not
// a missed rename: `"community"` is a *wire value* (the category id on the
// server and on stored user rows), so renaming the identifiers could only ever
// be half done. See CONTEXT.md.

import SwiftUI

enum MainTab: Hashable, CaseIterable {
    case today, cards, community, me

    var titleZh: LocalizedStringKey {
        switch self {
        // 今天, not 主頁: this tab's job is "what to do today", not "the front
        // page of the app". 我, not 我的 — the tab is you, not a folder of
        // things belonging to you.
        case .today: "今天"
        case .cards: "圖鑑"
        // 物見, not 社群: this tab is other people's *things seen*, not a place
        // with membership, a following graph or a conversation. The name says
        // what is in it, which is the same axis 圖鑑 sits on.
        case .community: "物見"
        case .me: "我"
        }
    }

    var iconName: String {
        switch self {
        case .today: "sun.max.fill"
        case .cards: "books.vertical.fill"
        // Binoculars, not two people: 物見 names things seen, and the two
        // person glyphs also made this tab and 我 read as a pair.
        case .community: "binoculars.fill"
        case .me: "person.fill"
        }
    }
}
