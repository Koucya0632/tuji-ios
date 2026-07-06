// First-run feature tour plumbing: highlight targets, the anchor
// preference that carries their frames up the tree, and the 5-step
// script. Views mark their highlight targets with .tourAnchor(_:);
// MainTabsView resolves the collected anchors and drives
// FeatureTourOverlay.

import SwiftUI

/// nonisolated: TourAnchorKey's nonisolated PreferenceKey members hash this
/// during layout, so the Hashable conformance can't be MainActor-isolated
/// (the project's default). The TestFlight (release/WMO) build enforces it.
nonisolated enum TourTarget: Hashable {
    /// Whole hero card on Today (guest fallback — guests have no CTA pair).
    case hero
    /// The 復習/學新字 button pair inside the hero (signed-in).
    case heroCTAs
    /// Daily-goal progress block inside the hero (signed-in only).
    case dailyGoal
    /// Streak chip in the Today top bar.
    case streak
    /// The floating tab bar pill.
    case tabBar
    /// Camera capture button in the 圖鑑 header.
    case capture
}

/// Merges every marked target's bounds into one dictionary read at the
/// MainTabsView level. Must stay nonisolated: the project defaults to
/// MainActor isolation, but PreferenceKey requirements are nonisolated
/// and evaluated during layout.
struct TourAnchorKey: PreferenceKey {
    nonisolated static var defaultValue: [TourTarget: Anchor<CGRect>] {
        [:]
    }

    nonisolated static func reduce(
        value: inout [TourTarget: Anchor<CGRect>],
        nextValue: () -> [TourTarget: Anchor<CGRect>]
    ) {
        value.merge(nextValue()) { $1 }
    }
}

extension View {
    func tourAnchor(_ target: TourTarget) -> some View {
        anchorPreference(key: TourAnchorKey.self, value: .bounds) { [target: $0] }
    }
}

enum TourCutoutShape {
    case rounded(CGFloat)
    /// Corner radius = half the cutout height (capsules, circular buttons).
    case pill
}

struct TourStep: Identifiable {
    let id: Int
    let tab: MainTab
    /// nil → no cutout; the card is centered (closing step).
    let target: TourTarget?
    /// Second choice when the target's anchor is missing from the tree.
    let fallback: TourTarget?
    let shape: TourCutoutShape
    let pose: MascotPose
    let title: LocalizedStringKey
    let text: LocalizedStringKey

    /// Guests get fallback targets (no CTA pair / goal bar) and copy that
    /// doesn't promise actions they can't take without an account.
    static func steps(isGuest: Bool) -> [TourStep] {
        [
            TourStep(
                id: 0,
                tab: .today,
                target: isGuest ? .hero : .heroCTAs,
                fallback: .hero,
                shape: isGuest ? .rounded(Radius.xl + 8) : .pill,
                pose: .wave,
                title: "每天從這裡開始",
                text: isGuest
                    ? "這裡是你的學習基地，建立帳號後就能學新字、排復習。"
                    : "點「學新字」認識新單字，用「復習」複習快忘記的字。"
            ),
            TourStep(
                id: 1,
                tab: .today,
                target: isGuest ? .streak : .dailyGoal,
                fallback: .streak,
                shape: isGuest ? .pill : .rounded(Radius.lg),
                pose: .think,
                title: "每日目標與連續天數",
                text: isGuest
                    ? "每天回來學習，火焰會記錄你的連續天數。"
                    : "完成今日目標，連續學習的火焰就會一天天累積。"
            ),
            TourStep(
                id: 2,
                tab: .today,
                target: .tabBar,
                fallback: nil,
                shape: .pill,
                pose: .face,
                title: "四個分頁",
                text: "主頁開始學習、圖鑑收集單字、進度查看成果、我的管理帳號。"
            ),
            TourStep(
                id: 3,
                tab: .cards,
                target: .capture,
                fallback: nil,
                shape: .pill,
                pose: .peek,
                title: "拍照收字",
                text: "Tuji 的招牌功能！對準身邊的物品拍一張，AI 幫你把它變成單字卡。"
            ),
            TourStep(
                id: 4,
                tab: .cards,
                target: nil,
                fallback: nil,
                shape: .rounded(Radius.xl),
                pose: .cheer,
                title: "開始你的第一課吧",
                text: "都準備好了，現在就開始今天的學習！"
            )
        ]
    }
}
