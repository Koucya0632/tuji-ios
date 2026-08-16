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
    /// The 複習/學新字 button pair inside the hero (signed-in).
    case heroCTAs
    /// Daily-goal progress block inside the hero (signed-in only).
    case dailyGoal
    /// Streak chip in the Today top bar.
    case streak
    /// The floating tab bar pill.
    case tabBar
    /// The 拍照 action in the middle of the tab bar.
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
                shape: isGuest ? .rounded(Radius.r0 + 8) : .pill,
                pose: .wave,
                title: "每天從這裡開始",
                text: isGuest
                    ? "這裡是你的學習基地，建立帳號後就能學新字、排複習。"
                    : "點「學新字」認識新單字，用「複習」複習快忘記的字。"
            ),
            TourStep(
                id: 1,
                tab: .today,
                target: isGuest ? .streak : .dailyGoal,
                fallback: .streak,
                shape: isGuest ? .pill : .rounded(Radius.r0),
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
                // Squared: the cutout frames the ink navigation slab, which is
                // a rectangle with the app's usual zero radius. It was a pill
                // when the bar was one full-width strip.
                shape: .rounded(Radius.r0),
                pose: .face,
                // This step has now been wrong four times. It first said
                // "四個分頁" listing 主頁/圖鑑/進度/我的 and missed 社群 entirely;
                // the fix added 社群 but kept three tab names that no longer
                // exist, so the tour pointed at the bar and read out 主頁, 進度
                // and 我的 to every new user; the count went stale the day 拍照
                // moved into the middle of the bar; and then *this* line said
                // "中間的黃色按鈕" the day 拍照 became its own block on the right.
                //
                // Counting them went wrong twice and pointing at them went
                // wrong once, so this copy now does neither: it names what each
                // one is for and lets the cutout say where. Whatever it says
                // must match what the bar renders, and there is still nothing
                // that makes a divergence fail to compile.
                title: "底下這一排",
                text: "今天開始學習、圖鑑收集單字、物見看大家收的東西、我查看成果與帳號，黃色按鈕隨時可以拍照收字。"
            ),
            TourStep(
                id: 3,
                // Stays on 今天: the capture slot is in the tab bar, so it is on
                // screen whichever tab is showing, and this step used to switch
                // to 圖鑑 only because that is where the button lived.
                tab: .today,
                target: .capture,
                fallback: nil,
                // Round, because what it frames is: `MascotEye` is the one
                // circle in the app. The cutout squared off for one release,
                // when 拍照 was briefly a rectangular yellow key.
                shape: .pill,
                pose: .peek,
                title: "拍照收字",
                // 拍照 needs an account (the upload is authenticated), so the
                // guest line says when it becomes theirs rather than telling
                // them to go do it now.
                text: isGuest
                    ? "Tuji 的招牌功能！建立帳號後，對準身邊的物品拍一張，AI 幫你把它變成單字卡。"
                    : "Tuji 的招牌功能！對準身邊的物品拍一張，AI 幫你把它變成單字卡。"
            ),
            TourStep(
                id: 4,
                tab: .cards,
                target: nil,
                fallback: nil,
                shape: .rounded(Radius.r0),
                pose: .cheer,
                // The closing step used to send guests off to "start today's
                // lesson" — the one thing a guest cannot do. Their hero CTA is
                // 建立帳號，開始學習, so the tour ends on the same ask.
                title: isGuest ? "建立帳號，開始學習" : "開始你的第一課吧",
                text: isGuest
                    ? "免費註冊就能學新字、排複習，進度存在雲端"
                    : "都準備好了，現在就開始今天的學習！"
            )
        ]
    }
}
