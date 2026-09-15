// The frame both study sessions sit in: how you leave one, and how a report is
// filed from inside it.
//
// Leaving is the rule this suite exists for. 複習 cancelled its beats and its
// audio when its screen went away and 學新字 did not — a swipe-back out of
// 學新字 still resolved the answer in flight and posted its SRS write. Both now
// reach one `leave()` through the shell, so these tests ask the shell, and ask
// each coordinator that its `leave()` does what the shell relies on.

import Foundation
import Testing
@testable import Tuji

@MainActor
struct StudySessionShellTests {
    // MARK: - Fixtures

    private func makeItem(
        id: String = "w-fork",
        cardId: String = "11",
        word: String = "fork"
    ) throws
        -> StudyQueueItem
    {
        let json = """
        {
          "card": { "id": "\(cardId)", "cardType": "flashcard", "deckKey": "core" },
          "word": {
            "id": "\(id)", "word": "\(word)", "chinese": "叉子", "imageUrl": "",
            "pronunciation": "", "reading": null, "targetLanguage": "en", "category": "kitchen"
          },
          "choices": ["\(word)", "spoon", "ladle", "whisk"],
          "spellingChoices": null,
          "mastery": 10
        }
        """
        return try JSONDecoder.tuji.decode(StudyQueueItem.self, from: Data(json.utf8))
    }

    // MARK: - Leaving

    /// Nothing is lost before the first card or after the last: ✕ goes, and
    /// the session is still told.
    @Test
    func closingWithNothingToLoseLeavesAtOnce() {
        let session = ShellSessionFake()
        let shell = StudySessionShell(kind: .new, session: session)

        let goes = shell.close(confirming: false)

        #expect(goes)
        #expect(session.leaves == 1)
        #expect(!shell.confirmingExit)
    }

    /// Mid-session ✕ asks, and asking is not leaving: 繼續 must find the beat
    /// still there.
    @Test
    func closingMidSessionAsksWithoutLeaving() {
        let session = ShellSessionFake()
        let shell = StudySessionShell(kind: .review, session: session)

        let goes = shell.close(confirming: true)

        #expect(!goes)
        #expect(shell.confirmingExit)
        #expect(session.leaves == 0)
    }

    /// 先離開 tells the session before the screen goes, and latches so a sheet
    /// the flow raises stays down through the pop.
    @Test
    func confirmingLeavesAndLatches() {
        let session = ShellSessionFake()
        let shell = StudySessionShell(kind: .review, session: session)
        _ = shell.close(confirming: true)

        shell.confirmLeave()

        #expect(session.leaves == 1)
        #expect(shell.leaving)
    }

    /// 再來一輪 swaps the coordinator under the same screen. Leaving afterwards
    /// must reach the new one, not the finished one.
    @Test
    func leavingReachesTheSessionSwappedIn() {
        let first = ShellSessionFake()
        let second = ShellSessionFake()
        let shell = StudySessionShell(kind: .review, session: first)

        shell.session = second
        shell.confirmLeave()

        #expect(first.leaves == 0)
        #expect(second.leaves == 1)
    }

    // MARK: - 報錯

    @Test
    func aReportIsFiledAgainstTheSessionsSubject() throws {
        let session = ShellSessionFake()
        let item = try self.makeItem()
        session.reportSubject = StudyReportSubject(item: item, phase: "reveal", selectedAnswer: "spoon")
        let shell = StudySessionShell(kind: .review, session: session)

        shell.report(uiLang: "ja")

        let draft = try #require(shell.reportDraft)
        #expect(draft.item == item)
        #expect(draft.mode == "review")
        #expect(draft.phase == "reveal")
        #expect(draft.selectedAnswer == "spoon")
        #expect(draft.uiLang == "ja")
        #expect(!shell.showsCustomCardNotice)
    }

    /// A 自製卡片 has no cards-table row, so there is nowhere to send it — the
    /// notice explains instead of a sheet that could only fail.
    @Test
    func aCustomCardExplainsInsteadOfFiling() throws {
        let session = ShellSessionFake()
        session.reportSubject = try StudyReportSubject(
            item: self.makeItem(id: "atlas:abc", cardId: "atlas:abc"),
            phase: "answer",
            selectedAnswer: nil
        )
        let shell = StudySessionShell(kind: .new, session: session)

        shell.report(uiLang: "zh-Hant")

        #expect(shell.reportDraft == nil)
        #expect(shell.showsCustomCardNotice)
    }

    @Test
    func noCardOnScreenFilesNothing() {
        let shell = StudySessionShell(kind: .new, session: ShellSessionFake())
        shell.report(uiLang: "en")
        #expect(shell.reportDraft == nil)
        #expect(!shell.showsCustomCardNotice)
    }

    // MARK: - What each session hands the shell

    /// 複習 reports what was ruled out while the question is still open —
    /// `picked` is only set by the pick that lands.
    @Test
    func reviewReportsTheOpenQuestionAndWhatWasRuledOut() throws {
        let c = try ReviewFlowCoordinator(
            queue: [self.makeItem()],
            writer: ShellWriterSpy(),
            beat: { _ in }
        )
        c.pick("spoon")

        let subject = try #require(c.reportSubject)
        #expect(subject.phase == "answer")
        #expect(subject.selectedAnswer == "spoon")
    }

    @Test
    func newFlowReportsTheStageOnScreen() throws {
        let c = try NewFlowCoordinator(queue: [self.makeItem()], writer: ShellWriterSpy(), beat: { _ in })
        let subject = try #require(c.reportSubject)
        #expect(subject.phase == NewTaskKind.recognize.rawValue)
        #expect(subject.selectedAnswer == nil)
    }

    /// The half 學新字 never had: leaving stops the headword 認識 may still be
    /// saying, as well as the beats.
    @Test
    func leavingNewFlowStopsItsAudio() throws {
        let audio = StopCountingSpeech()
        let c = try NewFlowCoordinator(
            queue: [self.makeItem()],
            writer: ShellWriterSpy(),
            audio: audio,
            beat: { _ in }
        )

        c.leave()

        #expect(audio.stops == 1)
    }
}

// MARK: - Doubles

@MainActor
private final class ShellSessionFake: StudySession {
    let writes = StudySessionWrites(writer: ShellWriterSpy())
    var reportSubject: StudyReportSubject?
    private(set) var leaves = 0

    func leave() {
        self.leaves += 1
    }
}

@MainActor
private final class ShellWriterSpy: DurableAnswerWriting {
    func submitAnswer(_: StudyAnswerPayload) async -> StudyWriteOutcome {
        .synced(StudyAnswerResponse(ok: true, milestone: nil, mastery: nil))
    }
}

@MainActor
private final class StopCountingSpeech: SpeechPlaying {
    private(set) var stops = 0

    func canPlay(_: String?, online _: Bool) -> Bool {
        false
    }

    func play(
        _: String?,
        text _: String,
        voice _: SpeechService.Voice,
        rate _: Float,
        onStart _: @escaping @MainActor () -> Void
    ) async
        -> SpeechPlayback
    {
        .finished
    }

    func stop() {
        self.stops += 1
    }
}
