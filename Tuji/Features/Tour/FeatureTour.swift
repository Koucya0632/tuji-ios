// First-run feature tour plumbing: highlight targets, the anchor
// preference that carries their frames up the tree, and the 4-step
// script. Views mark their highlight targets with .tourAnchor(_:);
// MainTabsView resolves the collected anchors and drives
// FeatureTourOverlay.

import SwiftUI

/// nonisolated: TourAnchorKey's nonisolated PreferenceKey members hash this
/// during layout, so the Hashable conformance can't be MainActor-isolated
/// (the project's default). The TestFlight (release/WMO) build enforces it.
nonisolated enum TourTarget: Hashable {
    /// Whole hero card on Today — the fallback when the CTA pair is missing.
    case hero
    /// The 複習/學新字 button pair inside the hero.
    case heroCTAs
    /// The cat on the Today hero, which is the way into 助手.
    case assistant
    /// The 拍照 action in the tab bar.
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

    /// Only what a new user would not find alone, all on 今天.
    ///
    /// The tab bar and the daily goal are no longer steps. The bar names its
    /// own tabs, and its step was wrong four times as they changed; each tab
    /// now introduces itself on the first visit (`TabTip`). The goal reads 0
    /// on day one and explains itself after the first lesson.
    static var steps: [TourStep] {
        [
            TourStep(
                id: 0,
                tab: .today,
                target: .heroCTAs,
                fallback: .hero,
                shape: .pill,
                pose: .wave,
                title: "每天從這裡開始",
                text: "學新字認識新單字，複習幫你記牢快忘的字。"
            ),
            TourStep(
                id: 1,
                tab: .today,
                // The cat gives no sign that it can be pressed — the speech
                // bubble beside it is the only hint — which makes it the one
                // thing on 今天 a new user is least likely to find.
                target: .assistant,
                fallback: nil,
                shape: .rounded(Radius.r0),
                pose: .face,
                title: "有問題就點我",
                text: "查單字、找收藏、問我問題都可以。"
            ),
            TourStep(
                id: 2,
                tab: .today,
                target: .capture,
                fallback: nil,
                // Round, because what it frames is: `MascotEye` is the one
                // circle in the app.
                shape: .pill,
                pose: .peek,
                title: "拍照收字",
                text: "拍下身邊的東西，變成你自己的單字卡。"
            ),
            TourStep(
                id: 3,
                tab: .today,
                target: nil,
                fallback: nil,
                shape: .rounded(Radius.r0),
                pose: .cheer,
                title: "先來學第一個字吧！",
                text: "跟著圖片認識今天的新單字。"
            )
        ]
    }
}

// MARK: - The flow

/// What advancing the tour means, once. The shell turns each of these into
/// animations and beats; none of that changes which one is right.
enum TourAdvance: Equatable {
    /// The next step is on the tab already showing.
    case show(index: Int)
    /// The next step lives elsewhere: switch, let the pager settle, then reveal.
    case crossTab(to: MainTab, index: Int)
    /// There is no next step.
    case finish
}

/// The tour as decisions rather than as `@State` on the tab shell.
///
/// It was ~60 lines inside `MainTabsView`: an index, a transitioning flag, a
/// four-condition start guard behind a 900 ms sleep, an advance that branched on
/// whether the next step lived on another tab, and a skip/finish pair that
/// differed only in a trailing `selected = .today`. `TourStep`, `advanceTour`
/// and `startTourIfNeeded` appeared in no test, and the only way to exercise
/// "the next step lives on another tab" was to launch the app.
///
/// Anchor resolution stays in the shell — `TourAnchorKey` merges up the view
/// tree and cannot be anywhere else. The index machine can.
struct FeatureTourFlow {
    let steps: [TourStep]

    init(steps: [TourStep] = TourStep.steps) {
        self.steps = steps
    }

    /// May the tour open at all?
    ///
    /// Checked *after* the splash beat, not before: all four of these can change
    /// while the shell waits, and the one that bit hardest is `pendingLink` — a
    /// deep link that arrives during the wait should win, because the user asked
    /// for it and the tour did not.
    static func mayStart(
        tourDone: Bool,
        studyFocusActive: Bool,
        hasPendingLink: Bool,
        alreadyRunning: Bool
    )
        -> Bool
    {
        !tourDone && !studyFocusActive && !hasPendingLink && !alreadyRunning
    }

    /// What happens when the reader taps 下一步 on `index`, given the tab they
    /// are looking at.
    func advance(from index: Int, showing tab: MainTab) -> TourAdvance {
        let next = index + 1
        guard next < self.steps.count else { return .finish }
        let step = self.steps[next]
        return step.tab == tab ? .show(index: next) : .crossTab(to: step.tab, index: next)
    }

    /// Where the shell lands when the tour ends by finishing rather than by
    /// being skipped. The closing card's 開始學習 opens 學新字, which lives on
    /// 今天 — so finishing goes there and skipping stays put.
    static let tabAfterFinishing: MainTab = .today

    /// What 開始學習 on the closing card opens.
    static let routeAfterFinishing: NavRoute = .studyLanding(mode: .new)
}
