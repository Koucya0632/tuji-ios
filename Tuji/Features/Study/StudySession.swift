// What 複習 and 學新字 have in common as *sessions*, as opposed to as questions:
// how you leave one, how you report the card in front of you, and what
// finishing it shows.
//
// Each flow carried its own copy of all of it — the exit prompt, the 報錯 menu,
// the `atlas:` check and the 自製卡片 notice, the report cover, the study-focus
// lifecycle, the milestone-or-summary branch and the analytics on either side.
// The copies had already drifted in the way that matters: 複習 learned to cancel
// its beats and its audio when its screen went away (#189) and 學新字 never
// did, so leaving 學新字 by any route other than the ✕ prompt still resolved the
// answer in flight — and posted its SRS write — on a screen that was gone.
//
// **Leaving is decided here, once.** Two things end a session: 先離開, and the
// screen being removed. Both call `leave()`. The second is only safe to key on
// `onDisappear` because nothing inside a session covers it with a push any more
// — see `WordDetailPresentation`, and why a push there was never just a cover.
//
// The seam is `StudySession`, which both coordinators satisfy. The view half
// (`studySessionShell`, `StudySessionNavBar`, `StudySessionFinish`) lives in
// `StudySessionShell.swift`; everything a test can ask about is on this side.

import Observation
import SwiftUI

/// What the shell needs from a running session.
@MainActor
protocol StudySession: AnyObject {
    /// Where the finish screen reads the milestone from, and what its refresh
    /// waits on.
    var writes: StudySessionWrites { get }

    /// The card a 報錯 filed right now would be about, or nil when there is no
    /// card on screen.
    var reportSubject: StudyReportSubject? { get }

    /// The user left. Drop the beats still waiting and cut any audio, so
    /// nothing resolves — or narrates — over the screen they went to.
    func leave()
}

/// The part of a 報錯 only the session knows: which card, at what point, and
/// what the user had chosen.
struct StudyReportSubject: Equatable {
    let item: StudyQueueItem
    let phase: String
    let selectedAnswer: String?
}

enum StudySessionKind {
    case review
    case new

    /// The analytics category and the report's `mode`, which have always been
    /// the same string.
    var wireName: String {
        switch self {
        case .review: "review"
        case .new: "new"
        }
    }
}

/// The shell's state for one session: the exit prompt, the report it is
/// composing, and whether the user has already chosen to go.
@MainActor
@Observable
final class StudySessionShell {
    let kind: StudySessionKind
    /// `var`, not `let`: 再來一輪 swaps in a fresh coordinator under the same
    /// screen.
    var session: StudySession

    /// The 要離開嗎？ prompt is up.
    var confirmingExit = false
    /// Latched by 先離開, so a sheet the flow raises stays down through the pop
    /// instead of flashing back up as the prompt closes.
    private(set) var leaving = false
    /// The report being filed, which raises the report cover.
    var reportDraft: StudyReportDraft?
    /// A 自製卡片 was reported; there is nowhere to send it.
    var showsCustomCardNotice = false

    init(kind: StudySessionKind, session: StudySession) {
        self.kind = kind
        self.session = session
    }

    /// ✕. Returns true when the screen should go straight away — nothing is
    /// lost before the first card or after the last — and false when the
    /// prompt is now asking.
    func close(confirming: Bool) -> Bool {
        guard confirming else {
            self.session.leave()
            return true
        }
        self.confirmingExit = true
        return false
    }

    /// 先離開. The caller dismisses after this.
    ///
    /// The session is told first: an answer given moments before ✕ still has
    /// a beat in flight, and without this it resolved after the screen was
    /// gone.
    func confirmLeave() {
        self.session.leave()
        self.leaving = true
    }

    /// 報錯 from the menu.
    ///
    /// Custom cards have no cards-table row, so /api/study/reports cannot
    /// accept them — explain instead of silently dropping the tap.
    func report(uiLang: String) {
        guard let subject = self.session.reportSubject else { return }
        guard subject.item.card.id.atlasItemId == nil else {
            self.showsCustomCardNotice = true
            return
        }
        self.reportDraft = StudyReportDraft(
            item: subject.item,
            mode: self.kind.wireName,
            phase: subject.phase,
            selectedAnswer: subject.selectedAnswer,
            uiLang: uiLang
        )
    }
}

/// How a word's full detail opens from inside a screen.
///
/// Pushing is right almost everywhere and wrong inside a study session, for a
/// reason that has nothing to do with taste: a session is shown through the
/// launcher's `navigationDestination(item:)`, and appending to the tab's path
/// while an item destination is on screen pops it — the launcher sees its item
/// go nil and dismisses. So a 詞塊 card's 看完整詳情 in 認識, in 複習's reveal
/// sheet or in the peek sheet ended the session the user was in the middle of.
/// A sheet leaves the session where it is, which is also what 複習's own
/// 看完整詳情 on the hint face has always done.
enum WordDetailPresentation {
    case push
    case sheet
}

extension EnvironmentValues {
    @Entry var wordDetailPresentation: WordDetailPresentation = .push
}
