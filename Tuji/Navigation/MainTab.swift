// The four primary tabs surfaced in MainTabsView.
//
// The semantic axis is 時間 → 內容 → 他人 → 自己: what to do today, all the
// words, other people's words, what you have accumulated. 進度 used to sit
// between 圖鑑 and 社群 and broke that line — it was not a *place*, it was a
// readout about you, which is what 我 is for. Its content moved there whole.

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
        case .community: "社群"
        case .me: "我"
        }
    }

    var iconName: String {
        switch self {
        case .today: "sun.max.fill"
        case .cards: "books.vertical.fill"
        case .community: "person.2.fill"
        case .me: "person.fill"
        }
    }
}
