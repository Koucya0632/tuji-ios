// The four primary tabs surfaced in MainTabsView.

import Foundation

enum MainTab: Hashable, CaseIterable {
    case today, cards, progress, me

    var titleZh: String {
        switch self {
        case .today: "今日"
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
