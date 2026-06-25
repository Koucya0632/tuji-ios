// The four primary tabs surfaced in MainTabsView.

import SwiftUI

enum MainTab: Hashable, CaseIterable {
    case today, cards, progress, me

    var titleZh: LocalizedStringKey {
        switch self {
        case .today: "主頁"
        case .cards: "圖鑑"
        case .progress: "進度"
        case .me: "我的"
        }
    }

    var iconName: String {
        switch self {
        case .today: "sun.max.fill"
        case .cards: "books.vertical.fill"
        case .progress: "chart.bar.fill"
        case .me: "person.fill"
        }
    }
}
