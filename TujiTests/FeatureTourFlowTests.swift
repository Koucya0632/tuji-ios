// Pins the five-step tour's index machine.
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
        let flow = FeatureTourFlow(isGuest: false)
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
        let flow = FeatureTourFlow(isGuest: false)
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
        let flow = FeatureTourFlow(isGuest: false)
        #expect(flow.advance(from: flow.steps.count - 1, showing: .today) == .finish)
    }

    /// The tab the reader is *looking at* decides, not the step's own tab: a
    /// reader who swiped the pager mid-tour is already where the next card is.
    @Test
    func theTabBeingShownDecidesNotTheStepsOwn() throws {
        let flow = FeatureTourFlow(isGuest: false)
        let boundary = try #require(
            (0..<(flow.steps.count - 1)).first { flow.steps[$0].tab != flow.steps[$0 + 1].tab }
        )
        let next = flow.steps[boundary + 1]
        // Already on the destination → no crossing needed.
        #expect(flow.advance(from: boundary, showing: next.tab) == .show(index: boundary + 1))
    }

    // MARK: - The two tours

    /// A guest gets a tour of what a guest can do. The two differ, which is why
    /// `steps(isGuest:)` takes the flag at all.
    @Test
    func theGuestTourIsItsOwnSequence() {
        let guest = FeatureTourFlow(isGuest: true)
        let signedIn = FeatureTourFlow(isGuest: false)
        #expect(!guest.steps.isEmpty)
        // A guest has no 學新字/複習 buttons, so the opening card points at the
        // hero itself rather than at CTAs that are not there.
        #expect(guest.steps[0].target != signedIn.steps[0].target)
    }

    /// Finishing lands on 主頁 because the closing card invites the reader to
    /// start today's study, which lives there. Skipping leaves them put — that
    /// one line is the entire difference between the two paths.
    @Test
    func finishingLandsWhereTheClosingCardPoints() {
        #expect(FeatureTourFlow.tabAfterFinishing == .today)
    }
}
