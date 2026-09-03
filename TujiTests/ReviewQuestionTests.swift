// One card's own rules, asked directly.
//
// These used to be reachable only through `ReviewFlowCoordinator`, which meant
// a beat, a clock nobody controlled, and — for anything past the pick — a
// 60-second poll on the reveal sheet. Every rule here is now a value in and a
// value out, so the whole answering path runs synchronously.
//
// The three this file exists for, because nothing asserted them before:
// the answer is timed exactly once (`measuredElapsed`), the payload carries
// that reading rather than a second one taken later, and `settled` is the one
// condition behind what used to be three `passedCount += 1` sites.

import Foundation
import Testing
@testable import Tuji

@MainActor
struct ReviewQuestionTests {
    // MARK: - Fixtures

    private func makeItem(
        id: String = "w-fork",
        word: String = "fork",
        mastery: Int = 10
    ) throws
        -> StudyQueueItem
    {
        let json = """
        {
          "card": { "id": 11, "cardType": "flashcard", "deckKey": "core" },
          "word": {
            "id": "\(id)", "word": "\(word)", "chinese": "叉子", "imageUrl": "",
            "pronunciation": "", "reading": null, "targetLanguage": "en", "category": "kitchen"
          },
          "choices": ["fork", "spoon", "ladle", "whisk"],
          "spellingChoices": null,
          "mastery": \(mastery)
        }
        """
        return try JSONDecoder.tuji.decode(StudyQueueItem.self, from: Data(json.utf8))
    }

    private func makeExample() throws -> StudyExample {
        let json = """
        {
          "sentence": "Pass me the fork.",
          "cefrLevel": "A2",
          "audioUrls": { "en-US": "https://example.test/a2.mp3" },
          "mentionedWordIds": ["w-fork"]
        }
        """
        return try JSONDecoder.tuji.decode(StudyExample.self, from: Data(json.utf8))
    }

    private let start = Date(timeIntervalSince1970: 1_700_000_000)

    private func makeQuestion(
        isRetest: Bool = false,
        mastery: Int = 10
    ) throws
        -> ReviewQuestion
    {
        try ReviewQuestion(
            item: self.makeItem(mastery: mastery),
            isRetest: isRetest,
            now: self.start
        )
    }

    // MARK: - The clock is read once

    /// The suggestion and the SRS row used to measure the answer separately —
    /// `resolve` refused to time one given before the clip finished, and
    /// `applyRating` recomputed it unconditionally 138 lines later, after the
    /// reveal beat and however long the user spent choosing a rating. One
    /// reading, taken when the answer lands.
    @Test
    func theAnswerIsTimedOnceAndThePayloadCarriesThatReading() throws {
        var q = try self.makeQuestion()
        _ = q.pick("fork", now: self.start.addingTimeInterval(5))
        #expect(q.measuredElapsed == 5)

        // A rating applied much later does not re-measure.
        let recorded = q.applyRating(.good)
        #expect(recorded)
        let payload = q.payload(rating: .good, listeningOptedOut: false)
        #expect(payload.responseMs == 5000)
    }

    /// 聽句 answered before its sentence finished: nothing was measured, so the
    /// row says so rather than reporting the download plus the clip.
    @Test
    func anAnswerGivenBeforeTheAudioEndedReportsNoDuration() throws {
        var q = try self.makeQuestion()
        try q.present(
            kind: .hearSentence,
            example: self.makeExample(),
            imageOptions: nil,
            awaitsAudio: true
        )
        #expect(q.awaitingAudio)

        _ = q.pick("fork", now: self.start.addingTimeInterval(30))
        #expect(q.measuredElapsed == nil)
        // 熟練 rests entirely on the speed signal, so an untimed correct answer
        // suggests 穩定 rather than inventing the evidence.
        #expect(q.suggested == .good)
        _ = q.applyRating(.good)
        #expect(q.payload(rating: .good, listeningOptedOut: false).responseMs == nil)
    }

    /// The first play opens the clock; a replay must not reset it, or the
    /// button becomes a way to buy time.
    @Test
    func onlyTheFirstPlaybackStartsTheClock() throws {
        var q = try self.makeQuestion()
        try q.present(
            kind: .hearSentence,
            example: self.makeExample(),
            imageOptions: nil,
            awaitsAudio: true
        )
        let began = q.playbackBegan()
        #expect(began)
        q.playbackEnded(.finished, isReplay: false, now: self.start.addingTimeInterval(2))
        #expect(!q.awaitingAudio)
        #expect(q.startedAt == self.start.addingTimeInterval(2))

        let replaying = q.willReplay()
        #expect(replaying)
        #expect(q.replayCount == 1)
        _ = q.playbackBegan()
        q.playbackEnded(.finished, isReplay: true, now: self.start.addingTimeInterval(9))
        #expect(q.startedAt == self.start.addingTimeInterval(2), "a replay must not reset the clock")
    }

    /// On-device synthesis reads kanji by a guess the app cannot correct, so
    /// the answer is not evidence about listening in either direction.
    @Test
    func aFallbackPlaybackIsRecordedAsAudioFailed() throws {
        var q = try self.makeQuestion()
        try q.present(
            kind: .hearSentence,
            example: self.makeExample(),
            imageOptions: nil,
            awaitsAudio: true
        )
        _ = q.playbackBegan()
        q.playbackEnded(.fallback, isReplay: false, now: self.start)
        #expect(q.audioFailed)
        #expect(!q.isPlayingSentence)

        _ = q.pick("fork", now: self.start)
        _ = q.applyRating(.good)
        let payload = q.payload(rating: .good, listeningOptedOut: false)
        #expect(payload.audioFailed == true)
        #expect(payload.replayCount == 0)
        #expect(payload.activity == "listening")
    }

    // MARK: - settled: one rule for the progress bar

    /// A re-test never requeues and is never rated, so it is done the moment it
    /// resolves — right or wrong.
    @Test
    func aRetestSettlesOnResolveEitherWay() throws {
        for correct in [true, false] {
            var q = try self.makeQuestion(isRetest: true)
            if !correct { _ = q.pick("spoon", now: self.start) }
            let tap = q.pick("fork", now: self.start)
            #expect(q.settled)
            #expect(tap == .resolved(correct ? .flashRetestPassed : .reveal(.continueOnly)))
        }
    }

    /// Anything else waits for the rating, and only a correct one clears the
    /// word — a wrong one goes back on the tail.
    @Test
    func aRatedAnswerSettlesOnlyWhenItWasCorrect() throws {
        var slow = try self.makeQuestion()
        _ = slow.pick("fork", now: self.start.addingTimeInterval(10))
        #expect(!slow.settled, "correct-but-slow is not done until it is rated")
        _ = slow.applyRating(.good)
        #expect(slow.settled)

        var missed = try self.makeQuestion()
        _ = missed.pick("spoon", now: self.start)
        _ = missed.pick("fork", now: self.start)
        _ = missed.applyRating(.again)
        #expect(!missed.settled, "a wrong answer is requeued, so nothing is cleared")
    }

    /// The auto-rate path applies its rating immediately, which is what makes
    /// the same rule true of it.
    @Test
    func anAutoRatedAnswerSettlesAsSoonAsItsRatingLands() throws {
        var q = try self.makeQuestion()
        let tap = q.pick("fork", now: self.start.addingTimeInterval(1))
        #expect(tap == .resolved(.autoRated(.good)))
        #expect(!q.settled, "not until the rating is recorded")
        _ = q.applyRating(.good)
        #expect(q.settled)
    }

    @Test
    func aRatingIsRecordedOnlyOnce() throws {
        var q = try self.makeQuestion()
        _ = q.pick("fork", now: self.start.addingTimeInterval(10))
        let first = q.applyRating(.hard)
        #expect(first)
        let second = q.applyRating(.easy)
        #expect(!second, "a second rating must not overwrite the first")
        #expect(q.rated == .hard)
    }

    @Test
    func countingIsIdempotent() throws {
        var q = try self.makeQuestion(isRetest: true)
        _ = q.pick("fork", now: self.start)
        #expect(!q.counted)
        q.markCounted()
        #expect(q.counted)
    }

    // MARK: - 看圖選字: ruling out is not answering

    /// A wrong option is marked and taken out of play while the question stays
    /// open; the pick that lands is still graded as a miss.
    @Test
    func aRuledOutOptionLeavesTheQuestionOpenAndStillCountsAsAMiss() throws {
        var q = try self.makeQuestion()
        let ruledOut = q.pick("spoon", now: self.start)
        #expect(ruledOut == .ruledOut)
        #expect(q.phase == .answer)
        #expect(q.wrongPicks == ["spoon"])
        // The same option again is not a second event.
        let repeated = q.pick("spoon", now: self.start)
        #expect(repeated == .ignored)

        let landed = q.pick("fork", now: self.start)
        #expect(landed == .resolved(.reveal(.rate)))
        #expect(!q.wasCorrect)
        #expect(q.suggested == .again)
        #expect(q.availableRatings == [.again, .hard])
    }

    /// 報錯 filed mid-question keeps what the user has already tried; `picked`
    /// is only set by the pick that lands.
    @Test
    func theReportedSelectionSurvivesAnUnfinishedQuestion() throws {
        var q = try self.makeQuestion()
        #expect(q.reportedSelection == nil)
        _ = q.pick("spoon", now: self.start)
        _ = q.pick("ladle", now: self.start)
        #expect(q.reportedSelection == "ladle / spoon")
        _ = q.pick("fork", now: self.start)
        #expect(q.reportedSelection == "fork")
    }

    /// 選字's options are labels and carry no id; a picture carries the
    /// catalogue id, and that is what the frame has to match on.
    @Test
    func aPickCarriesAnIdOnlyWhenTheOptionHadOne() throws {
        var mcq = try self.makeQuestion()
        _ = mcq.pick("fork", now: self.start)
        #expect(mcq.picked == ReviewChoice(id: nil, label: "fork"))

        var listening = try self.makeQuestion()
        try listening.present(
            kind: .hearSentence,
            example: self.makeExample(),
            imageOptions: nil,
            awaitsAudio: false
        )
        let option = ImageChoiceOption(
            id: "w-fork",
            word: "fork",
            imageUrl: "",
            imageKind: .cutout
        )
        _ = listening.pickImage(option, now: self.start)
        #expect(listening.picked == ReviewChoice(id: "w-fork", label: "fork"))
    }

    /// Ruling out one of *two* pictures is the same act as answering, so 聽句
    /// resolves on the first tap (ADR-0014).
    @Test
    func aWrongPictureResolvesImmediately() throws {
        var q = try self.makeQuestion()
        try q.present(
            kind: .hearSentence,
            example: self.makeExample(),
            imageOptions: nil,
            awaitsAudio: false
        )
        let other = ImageChoiceOption(
            id: "w-spoon",
            word: "spoon",
            imageUrl: "",
            imageKind: .cutout
        )
        let tap = q.pickImage(other, now: self.start)
        #expect(tap == .resolved(.reveal(.rate)))
        #expect(!q.wasCorrect)
        #expect(q.phase == .review)
    }

    /// Compared by id, not by label: two catalogue words can print the same
    /// string, they cannot share an id.
    @Test
    func aPictureIsJudgedByIdNotByItsLabel() throws {
        var q = try self.makeQuestion()
        try q.present(
            kind: .hearSentence,
            example: self.makeExample(),
            imageOptions: nil,
            awaitsAudio: false
        )
        // Same label as the answer, different word.
        let impostor = ImageChoiceOption(
            id: "w-other-fork",
            word: "fork",
            imageUrl: "",
            imageKind: .cutout
        )
        _ = q.pickImage(impostor, now: self.start)
        #expect(!q.wasCorrect)
    }

    // MARK: - 求救提示 and the blur

    @Test
    func theHintIsStickyAndTakesTheWrongAnswerTable() throws {
        var q = try self.makeQuestion()
        #expect(q.canNudge)
        q.toggleHint()
        #expect(q.hinted)
        #expect(q.hintFaceUp)
        #expect(!q.canNudge)
        q.toggleHint()
        #expect(!q.hintFaceUp)
        #expect(q.hinted, "flipping back does not un-see it")

        _ = q.pick("fork", now: self.start.addingTimeInterval(1))
        #expect(q.wasCorrect)
        #expect(q.suggested == .hard, "capped, which is what switches off auto-rating")
        #expect(q.availableRatings == [.again, .hard])
    }

    /// The hint is a 選字 affordance; the blur is 聽句's, and costs the same.
    @Test
    func liftingTheBlurCostsWhatTheFlipCosts() throws {
        var q = try self.makeQuestion()
        try q.present(
            kind: .hearSentence,
            example: self.makeExample(),
            imageOptions: nil,
            awaitsAudio: false
        )
        q.toggleHint()
        #expect(!q.hinted, "there is no card to flip in 聽句")
        #expect(!q.canNudge, "and no nudge to give about one")

        q.revealSentence()
        #expect(q.sentenceRevealed)
        #expect(q.hinted)
    }

    /// Answering ends the cost: the sentence is teaching material from then on.
    @Test
    func theBlurIsFreeOnceTheAnswerIsIn() throws {
        var q = try self.makeQuestion()
        try q.present(
            kind: .hearSentence,
            example: self.makeExample(),
            imageOptions: nil,
            awaitsAudio: false
        )
        _ = q.pick("fork", now: self.start)
        q.revealSentence()
        #expect(!q.sentenceRevealed, "the flag is the answering-phase one")
        #expect(!q.hinted)
    }

    // MARK: - 這輪不做聽句題

    /// It changes the question rather than revealing anything, so the clock
    /// restarts and nothing is marked `hinted`.
    @Test
    func optingOutConvertsTheCardAndRestartsTheClock() throws {
        var q = try self.makeQuestion()
        try q.present(
            kind: .hearSentence,
            example: self.makeExample(),
            imageOptions: nil,
            awaitsAudio: true
        )
        let optedOut = q.optOutOfListening(now: self.start.addingTimeInterval(4))
        #expect(optedOut)
        #expect(q.kind == .pickWord)
        #expect(q.example == nil)
        #expect(!q.awaitingAudio)
        #expect(!q.hinted)
        #expect(q.startedAt == self.start.addingTimeInterval(4))
        #expect(q.convertedFromListening)

        // The card the user bailed on is the sharpest datum, and its activity
        // honestly says what was answered.
        _ = q.pick("fork", now: self.start.addingTimeInterval(5))
        _ = q.applyRating(.good)
        let payload = q.payload(rating: .good, listeningOptedOut: true)
        #expect(payload.activity == "mcq")
        #expect(payload.convertedFromListening == true)
        #expect(payload.listeningOptedOut == true)
        #expect(payload.replayCount == nil, "not a listening row any more")
    }

    /// `listeningOptedOut` rides on every activity — rows that cannot be told
    /// apart from a session that never met a listening question are what makes
    /// an aggregate accuracy lie. Absent, not `false`, on an ordinary session.
    @Test
    func anOrdinarySessionSaysNothingAboutListening() throws {
        var q = try self.makeQuestion()
        _ = q.pick("fork", now: self.start.addingTimeInterval(1))
        _ = q.applyRating(.good)
        let payload = q.payload(rating: .good, listeningOptedOut: false)
        #expect(payload.listeningOptedOut == nil)
        #expect(payload.convertedFromListening == nil)
        #expect(payload.replayCount == nil)
        #expect(payload.audioFailed == nil)
    }

    /// Opting out is only for the phase and the kind it applies to.
    @Test
    func optingOutIsRefusedOnceAnsweredOrOnAPickWordCard() throws {
        var mcq = try self.makeQuestion()
        let refusedOnMCQ = mcq.optOutOfListening(now: self.start)
        #expect(!refusedOnMCQ)

        var answered = try self.makeQuestion()
        try answered.present(
            kind: .hearSentence,
            example: self.makeExample(),
            imageOptions: nil,
            awaitsAudio: false
        )
        _ = answered.pick("fork", now: self.start)
        let refusedAfterAnswer = answered.optOutOfListening(now: self.start)
        #expect(!refusedAfterAnswer)
    }

    // MARK: - Presenting

    /// A card with no sentence keeps none of 聽句's state, whatever it was
    /// asked for.
    @Test
    func presentingWithoutASentenceLeavesAPickWordCard() throws {
        var q = try self.makeQuestion()
        #expect(!q.ready)
        q.present(kind: .hearSentence, example: nil, imageOptions: nil, awaitsAudio: true)
        #expect(q.ready)
        #expect(q.kind == .pickWord, "a sentence is what makes it a listening question")
        #expect(q.example == nil)
        #expect(!q.awaitingAudio)
        let nothingToPlay = q.playbackBegan()
        #expect(!nothingToPlay, "and nothing to play")
    }

    // MARK: - The suggestion table

    @Test
    func theSuggestionCapsEasyForLowMastery() {
        #expect(ReviewQuestion.suggestion(correct: true, elapsed: 1, mastery: 10) == .good)
        #expect(ReviewQuestion.suggestion(correct: true, elapsed: 1, mastery: 80) == .easy)
        #expect(ReviewQuestion.suggestion(correct: true, elapsed: 5, mastery: 80) == .good)
        #expect(ReviewQuestion.suggestion(correct: true, elapsed: 10, mastery: 80) == .hard)
        #expect(ReviewQuestion.suggestion(correct: false, elapsed: 1, mastery: 80) == .again)
        #expect(ReviewQuestion.suggestion(correct: true, elapsed: nil, mastery: 80) == .good)
        #expect(
            ReviewQuestion.suggestion(correct: true, elapsed: 1, mastery: 80, hinted: true) == .hard
        )
    }
}
