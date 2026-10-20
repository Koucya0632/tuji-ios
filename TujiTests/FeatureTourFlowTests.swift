// Pins the tour's index machine.
//
// It was ~60 lines of `@State` and private methods on `MainTabsView`: a
// four-condition start guard behind a 900 ms sleep, an advance that branched on
// whether the next step lived on another tab, and a skip/finish pair that
// differed only in a trailing `selected = .today`. None of it appeared in a
// test, and the only way to exercise the cross-tab branch was to launch the app
// and tap through five cards.

import Foundation
import Testing
@testable import Tuji

struct FeatureTourFlowTests {
    // MARK: - May it start

    @Test
    func afreshInstallStartsTheTour() {
        #expect(FeatureTourFlow.mayStart(
            tourDone: false,
            studyFocusActive: false,
            hasPendingLink: false,
            alreadyRunning: false
        ))
    }

    /// Each of the four on its own is enough to keep it shut. They are re-asked
    /// *after* the splash beat, because every one of them can change while the
    /// shell waits.
    @Test
    func anyOneReasonKeepsItShut() {
        #expect(!FeatureTourFlow.mayStart(
            tourDone: true, studyFocusActive: false, hasPendingLink: false, alreadyRunning: false
        ))
        #expect(!FeatureTourFlow.mayStart(
            tourDone: false, studyFocusActive: true, hasPendingLink: false, alreadyRunning: false
        ))
        #expect(!FeatureTourFlow.mayStart(
            tourDone: false, studyFocusActive: false, hasPendingLink: true, alreadyRunning: false
        ))
        #expect(!FeatureTourFlow.mayStart(
            tourDone: false, studyFocusActive: false, hasPendingLink: false, alreadyRunning: true
        ))
    }

    /// The one worth naming: a deep link that lands during the 900 ms wait wins.
    /// The reader asked for that screen; the tour did not.
    @Test
    func aDeepLinkArrivingDuringTheWaitWins() {
        #expect(!FeatureTourFlow.mayStart(
            tourDone: false,
            studyFocusActive: false,
            hasPendingLink: true,
            alreadyRunning: false
        ))
    }

    // MARK: - Advancing

    /// A pair on one tab, asserted rather than skipped when absent: a test whose
    /// premise can quietly stop holding is a test that passes by absence.
    @Test
    func aStepOnTheSameTabJustShowsTheNextOne() throws {
        let flow = FeatureTourFlow()
        let pair = try #require(
            (0..<(flow.steps.count - 1)).first { flow.steps[$0].tab == flow.steps[$0 + 1].tab },
            "the tour no longer has two consecutive steps on one tab"
        )
        #expect(flow.advance(from: pair, showing: flow.steps[pair].tab) == .show(index: pair + 1))
    }

    /// The branch that could only be reached by launching the app: the next
    /// card lives on another tab, so the pager has to move first.
    @Test
    func aStepOnAnotherTabCrossesToIt() throws {
        let flow = Self.crossTabFlow
        let boundary = try #require(
            (0..<(flow.steps.count - 1)).first { flow.steps[$0].tab != flow.steps[$0 + 1].tab },
            "the tour no longer changes tab; this branch has nothing to pin"
        )
        let next = flow.steps[boundary + 1]
        #expect(flow.advance(from: boundary, showing: flow.steps[boundary].tab)
            == .crossTab(to: next.tab, index: boundary + 1))
    }

    /// Advancing off the end finishes rather than trapping or showing a blank
    /// card — the guard that used to be `index + 1 < steps.count` inline.
    @Test
    func advancingPastTheLastStepFinishes() {
        let flow = FeatureTourFlow()
        #expect(flow.advance(from: flow.steps.count - 1, showing: .today) == .finish)
    }

    /// The tab the reader is *looking at* decides, not the step's own tab: a
    /// reader who swiped the pager mid-tour is already where the next card is.
    @Test
    func theTabBeingShownDecidesNotTheStepsOwn() throws {
        let flow = Self.crossTabFlow
        let boundary = try #require(
            (0..<(flow.steps.count - 1)).first { flow.steps[$0].tab != flow.steps[$0 + 1].tab }
        )
        let next = flow.steps[boundary + 1]
        // Already on the destination → no crossing needed.
        #expect(flow.advance(from: boundary, showing: next.tab) == .show(index: boundary + 1))
    }

    /// Finishing lands on 主頁 because the closing card invites the reader to
    /// start today's study, which lives there. Skipping leaves them put — that
    /// one line is the entire difference between the two paths.
    @Test
    func finishingLandsWhereTheClosingCardPoints() {
        #expect(FeatureTourFlow.tabAfterFinishing == .today)
        #expect(FeatureTourFlow.routeAfterFinishing == .studyLanding(mode: .new))
    }

    /// The shipped script stays on 今天 — each other tab introduces itself
    /// instead (`TabTip`) — and ends on the card that starts 學新字.
    @Test
    func theScriptStaysOnTodayAndEndsOnTheClosingCard() {
        let steps = TourStep.steps
        #expect(steps.allSatisfy { $0.tab == .today })
        #expect(steps.last?.target == nil)
        #expect(steps.map(\.id) == Array(steps.indices))
    }

    /// The cross-tab branch is kept for a script that needs it; the shipped one
    /// does not, so it is pinned against a two-tab fixture.
    private static let crossTabFlow = FeatureTourFlow(steps: [
        TourStep(
            id: 0,
            tab: .today,
            target: .heroCTAs,
            fallback: nil,
            shape: .pill,
            pose: .wave,
            title: "a",
            text: "a"
        ),
        TourStep(id: 1, tab: .cards, target: nil, fallback: nil, shape: .pill, pose: .cheer, title: "b", text: "b")
    ])
}

struct TabTipTests {
    private func shows(
        _ tab: MainTab,
        armed: Bool = true,
        seen: Set<String> = [],
        atRoot: Bool = true,
        tourRunning: Bool = false,
        studyFocusActive: Bool = false
    )
        -> Bool
    {
        TabTip.shows(
            on: tab, armed: armed, seen: seen, atRoot: atRoot,
            tourRunning: tourRunning, studyFocusActive: studyFocusActive
        )
    }

    @Test
    func everyTabButTodayHasATip() {
        for tab in MainTab.allCases {
            #expect((TabTip.key(for: tab) != nil) == (tab != .today))
            #expect((TabTip.text(for: tab) != nil) == (tab != .today))
        }
    }

    @Test
    func aFreshTabAtItsRootShowsItsTip() {
        #expect(self.shows(.cards))
        #expect(!self.shows(.today))
    }

    /// Someone who took the old tour never armed them.
    @Test
    func unarmedSeenOrBusyKeepsItHidden() {
        #expect(!self.shows(.cards, armed: false))
        #expect(!self.shows(.cards, seen: ["cards"]))
        #expect(!self.shows(.cards, atRoot: false))
        #expect(!self.shows(.cards, tourRunning: true))
        #expect(!self.shows(.cards, studyFocusActive: true))
    }
}
