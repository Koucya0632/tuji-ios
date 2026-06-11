// The five primary tabs surfaced in MainTabsView. The center tab is
// visually elevated ("中央凸起") and reserved for the Tuji mascot launcher.

import Foundation

enum MainTab: Hashable, CaseIterable {
    case today, cards, tuji, progress, me

    var titleZh: String {
        switch self {
        case .today: "今日"
        case .cards: "圖鑑"
        case .tuji: "Tuji"
        case .progress: "進度"
        case .me: "我的"
        }
    }

    var iconName: String {
        switch self {
        case .today: "sun.max.fill"
        case .cards: "books.vertical.fill"
        case .tuji: "sparkles"
        case .progress: "chart.bar.fill"
        case .me: "person.fill"
        }
    }
}
