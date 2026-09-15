// 聽句: the sentence ladder, the question spacing, the picture pair, and the
// three rating rules that differ from 選字.
//
// The rules worth pinning here are the ones that are invisible on screen and
// expensive to be wrong about: a 50% guess must never reach the auto-rate path,
// the clock must not start until the audio ends (and a replay must not reset
// it), and a distractor must never be a word the sentence itself names — that
// last one makes the question unanswerable while looking perfectly fine.

import Foundation
import Testing
@testable import Tuji

/// Behaves like the one speaker the app has: a new play cuts the previous one
/// off, and the previous one learns it was superseded. The fake this replaces
/// returned each play's own outcome, so a replay during the first play looked
/// harmless here while it marked the audio failed on devices.
@MainActor
private final class FakeSpeechPlaying: SpeechPlaying {
    var playable = true
    var outcome: SpeechPlayback = .finished
    private(set) var plays: [String?] = []
    /// Set to hold `play` open so a test can answer mid-sentence.
    var holdsPlayback = false
    /// False models a clip still downloading when the timeout comes round.
    var startsImmediately = true
    private var held: CheckedContinuation<SpeechPlayback, Never>?

    var isHolding: Bool {
        self.held != nil
    }

    private(set) var stopped = 0

    func stop() {
        self.stopped += 1
        self.release(.stopped)
    }

    func canPlay(_ urlString: String?, online: Bool) -> Bool {
        guard urlString != nil else { return false }
        return self.playable && online
    }

    private(set) var rates: [Float] = []
    private(set) var voices: [SpeechService.Voice] = []

    /// Ends the held play with `outcome`.
    func release(_ outcome: SpeechPlayback? = nil) {
        let pending = self.held
        self.held = nil
        pending?.resume(returning: outcome ?? self.outcome)
    }

    func play(
        _ urlString: String?,
        text _: String,
        voice: SpeechService.Voice,
        rate: Float,
        onStart: @escaping @MainActor () -> Void
    ) async
        -> SpeechPlayback
    {
        self.plays.append(urlString)
        self.rates.append(rate)
        self.voices.append(voice)
        self.release(.superseded)
        if self.startsImmediately { onStart() }
        guard self.holdsPlayback else { return self.outcome }
        return await withCheckedContinuation { self.held = $0 }
    }
}

@MainActor
struct ReviewListeningTests {
    // MARK: - Fixtures

    /// Two words, each with the authored A2/B1 pair. `w-mug`'s sentence names
    /// `w-plate` too — the 46%-of-sentences case the distractor rule exists
    /// for. Its id also hashes onto a 聽句 slot, which the fixture has to do
    /// deliberately: an id that does not would leave every listening
    /// assertion below passing against a 選字 card.
    private func makeQueue() throws -> [StudyQueueItem] {
        let json = """
        [
          {
            "card": { "id": 11, "cardType": "flashcard", "deckKey": "core" },
            "word": {
              "id": "w-mug", "word": "mug", "chinese": "馬克杯", "imageUrl": "https://x/mug.webp",
              "pronunciation": "", "reading": null, "targetLanguage": "en", "category": "kitchen"
            },
            "choices": ["mug", "spoon", "ladle", "whisk"],
            "spellingChoices": null,
            "mastery": 10,
            "examples": [
              { "sentence": "The mug is next to the plate.", "cefrLevel": "A2",
                "audioUrls": { "en-US": "https://a/mug-a2.mp3" },
                "mentionedWordIds": ["w-mug", "w-plate"] },
              { "sentence": "Rinse the mug before you pour the tea.",
                "cefrLevel": "B1",
                "audioUrls": { "en-US": "https://a/mug-b1.mp3" },
                "mentionedWordIds": ["w-mug"] }
            ]
          },
          {
            "card": { "id": 22, "cardType": "flashcard", "deckKey": "core" },
            "word": {
              "id": "w-cup", "word": "cup", "chinese": "杯子", "imageUrl": "https://x/cup.webp",
              "pronunciation": "", "reading": null, "targetLanguage": "en", "category": "kitchen"
            },
            "choices": ["cup", "plate", "bowl", "jar"],
            "spellingChoices": null,
            "mastery": 80,
            "examples": [
              { "sentence": "The cup is on the table.", "cefrLevel": "A2",
                "audioUrls": { "en-US": "https://a/cup-a2.mp3" },
                "mentionedWordIds": ["w-cup"] },
              { "sentence": "Rinse the cup before you pour the tea.", "cefrLevel": "B1",
                "audioUrls": { "en-US": "https://a/cup-b1.mp3" },
                "mentionedWordIds": ["w-cup"] }
            ]
          }
        ]
        """
        return try JSONDecoder.tuji.decode([StudyQueueItem].self, from: Data(json.utf8))
    }

    private func pool() -> [CardWord] {
        [
            CardWord(
                id: "w-cup", word: "cup", chinese: "杯子",
                imageUrl: "https://x/cup.webp", category: "kitchen",
                pronunciation: "", targetLanguage: .en
            ),
            CardWord(
                id: "w-plate", word: "plate", chinese: "盤子",
                imageUrl: "https://x/plate.webp", category: "kitchen",
                pronunciation: "", targetLanguage: .en
            ),
            CardWord(
                id: "w-photo", word: "my kettle", chinese: "水壺",
                imageUrl: "https://x/kettle.webp", category: "custom",
                pronunciation: "", targetLanguage: .en
            )
        ]
    }

    /// The rating sheet rises a beat (`revealDelay`) after an answer resolves,
    /// so it is never observable in the same turn as the pick.
    ///
    /// Requires the sheet rather than just polling for it: `waitUntil` returns
    /// quietly when it times out, so calling this on a path that auto-rates —
    /// which raises no sheet at all — would spend the whole 60s ceiling and
    /// still pass.
    private func awaitReveal(_ c: ReviewFlowCoordinator) async throws {
        try await self.waitUntil { c.revealMode != nil }
        try #require(c.revealMode != nil, "the reveal sheet never rose")
    }

    private func waitUntil(
        timeout: Duration = .seconds(60),
        _ condition: () -> Bool
    ) async throws {
        let deadline = ContinuousClock.now + timeout
        while !condition(), ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(50))
        }
    }

    // MARK: - Which sentence

    @Test
    func lowMasteryTakesTheSimplerSentence() throws {
        let item = try makeQueue()[0]
        let example = ListeningQuestion.example(for: item, mastery: 10, presentation: 0)
        #expect(example?.cefrLevel == "A2")
    }

    @Test
    func establishedWordTakesTheHarderSentence() throws {
        let item = try makeQueue()[0]
        let example = ListeningQuestion.example(for: item, mastery: 80, presentation: 0)
        #expect(example?.cefrLevel == "B1")
    }

    @Test
    func theTierThresholdIsTheOneComputeSuggestionUses() throws {
        let item = try makeQueue()[0]
        #expect(ListeningQuestion.example(for: item, mastery: 49, presentation: 0)?.cefrLevel == "A2")
        #expect(ListeningQuestion.example(for: item, mastery: 50, presentation: 0)?.cefrLevel == "B1")
    }

    /// Replaying the recording the user just failed is not practice.
    @Test
    func aRetestHearsTheOtherSentence() throws {
        let item = try makeQueue()[0]
        let first = ListeningQuestion.example(for: item, mastery: 10, presentation: 0)
        let retest = ListeningQuestion.example(for: item, mastery: 10, presentation: 1)
        #expect(first?.cefrLevel == "A2")
        #expect(retest?.cefrLevel == "B1")
    }

    /// Two sentences and a third look: clamp rather than wrap, so it does not
    /// start alternating between two things it has already played.
    @Test
    func aThirdLookClampsInsteadOfWrapping() throws {
        let item = try makeQueue()[0]
        #expect(ListeningQuestion.example(for: item, mastery: 10, presentation: 5)?.cefrLevel == "B1")
    }

    @Test
    func aCardWithNoSentencesIsNotAskable() throws {
        let json = """
        { "card": { "id": 1, "cardType": "flashcard", "deckKey": "core" },
          "word": { "id": "atlas:1", "word": "kettle", "chinese": "水壺", "imageUrl": "",
                    "pronunciation": "", "reading": null, "targetLanguage": "en",
                    "category": "custom" },
          "choices": null, "spellingChoices": null, "mastery": 0 }
        """
        let item = try JSONDecoder.tuji.decode(StudyQueueItem.self, from: Data(json.utf8))
        #expect(ListeningQuestion.example(for: item, mastery: 0, presentation: 0) == nil)
    }

    // MARK: - Which question

    @Test
    func noPlayableClipMeansPickWord() {
        let kind = ListeningQuestion.kind(
            wordId: "w-mug", canHear: false, previous: nil, alreadyHeard: false
        )
        #expect(kind == .pickWord)
    }

    @Test
    func twoListeningQuestionsNeverRunBackToBack() throws {
        // A word that does fall on a slot, offered right after another 聽句.
        let onSlot = (0..<400).map(String.init).first { ListeningQuestion.fallsOnSlot(wordId: $0) }
        let word = try #require(onSlot)
        #expect(ListeningQuestion.kind(
            wordId: word, canHear: true, previous: nil, alreadyHeard: false
        ) == .hearSentence)
        #expect(ListeningQuestion.kind(
            wordId: word, canHear: true, previous: .hearSentence, alreadyHeard: false
        ) == .pickWord)
    }

    /// A re-test is practice on what was missed and writes no SRS, so the
    /// spacing rule — which exists to stop clusters of *scored* listening
    /// questions — does not demote it.
    @Test
    func aRetestKeepsItsQuestionEvenBackToBack() {
        let kind = ListeningQuestion.kind(
            wordId: "anything", canHear: true, previous: .hearSentence, alreadyHeard: true
        )
        #expect(kind == .hearSentence)
    }

    @Test
    func aboutOneCardInFourFallsOnASlot() {
        let hits = (0..<2000).count { ListeningQuestion.fallsOnSlot(wordId: "word-\($0)") }
        #expect((400...600).contains(hits))
    }

    @Test
    func theSlotDoesNotMoveBetweenCalls() {
        let first = ListeningQuestion.fallsOnSlot(wordId: "w-mug")
        #expect(ListeningQuestion.fallsOnSlot(wordId: "w-mug") == first)
    }

    // MARK: - Which pictures

    /// The sentence names the cup as well as the fork. Offering both makes the
    /// question unanswerable while looking entirely normal.
    @Test
    func aWordTheSentenceAlsoNamesIsNeverTheDistractor() throws {
        let item = try makeQueue()[0]
        let options = ImageChoicePair.options(
            for: item,
            pool: self.pool(),
            session: .en,
            mentionedWordIds: ["w-mug", "w-plate"],
            queuedWordIds: []
        )
        let ids = try #require(options).map(\.id)
        #expect(ids.contains("w-mug"))
        #expect(!ids.contains("w-plate"), "the sentence names the plate too")
    }

    @Test
    func aCardStillQueuedIsNeverTheDistractor() throws {
        let item = try makeQueue()[0]
        let options = ImageChoicePair.options(
            for: item,
            pool: self.pool(),
            session: .en,
            mentionedWordIds: ["w-mug"],
            queuedWordIds: ["w-cup"]
        )
        let ids = try #require(options).map(\.id)
        #expect(!ids.contains("w-cup"))
    }

    /// A cut-out beside a photograph answers itself.
    @Test
    func aPhotographNeverStandsBesideACutout() throws {
        let item = try makeQueue()[0]
        let options = ImageChoicePair.options(
            for: item,
            pool: self.pool(),
            session: .en,
            mentionedWordIds: ["w-mug", "w-plate"],
            queuedWordIds: ["w-cup"]
        )
        // Only the custom photograph is left in the pool — and it is refused,
        // so the caller falls back to 選字 rather than asking a giveaway.
        #expect(options == nil)
    }

    @Test
    func theOrderIsStableAcrossRedraws() throws {
        let item = try makeQueue()[0]
        let a = ImageChoicePair.options(
            for: item, pool: self.pool(), session: .en,
            mentionedWordIds: [], queuedWordIds: []
        )
        let b = ImageChoicePair.options(
            for: item, pool: self.pool(), session: .en,
            mentionedWordIds: [], queuedWordIds: []
        )
        #expect(a?.map(\.id) == b?.map(\.id))
    }

    // MARK: - Highlighting the word inside its sentence

    private func marked(_ word: String, _ sentence: String) -> String? {
        SentenceHighlight.range(of: word, in: sentence).map { String(sentence[$0]) }
    }

    @Test
    func theHeadwordIsFoundInItsOwnSentence() {
        #expect(self.marked("fork", "The fork is next to the plate.") == "fork")
    }

    @Test
    func theMatchIgnoresCase() {
        #expect(self.marked("highlighter", "Highlighter ink bleeds through.") == "Highlighter")
    }

    /// Ten sentences in the live corpus name the word in the plural. Stopping
    /// at the singular leaves the last letter outside the highlighter, which
    /// reads as a rendering bug rather than a decision.
    @Test
    func aPluralIsHighlightedWhole() {
        #expect(self.marked("curtain", "Please open the curtains.") == "curtains")
        #expect(self.marked("traffic cone", "The traffic cones mark the work area.") == "traffic cones")
        #expect(self.marked("monitor", "I have two monitors at my desk.") == "monitors")
    }

    /// The reason the plural suffix is `s`/`es` and not "any trailing letters":
    /// a loose rule points the highlighter at a different word entirely.
    @Test
    func aWordIsNeverHighlightedInsideALongerOne() {
        #expect(self.marked("cup", "The cupboard is above the sink.") == nil)
        #expect(self.marked("grate", "I bought a new grater.") == nil)
    }

    @Test
    func aSecondOccurrenceIsFoundWhenTheFirstIsInsideAnotherWord() {
        #expect(self.marked("cup", "The cupboard holds one cup.") == "cup")
    }

    /// Japanese has no word boundaries, so the Latin boundary rule must not be
    /// applied to it — every kana neighbour is a letter, and requiring a
    /// non-letter would reject every Japanese sentence there is.
    @Test
    func japaneseMatchesAsAPlainSubstring() {
        #expect(self.marked("エアコン", "エアコンは寝室にあります。") == "エアコン")
        #expect(self.marked("寝室", "エアコンは寝室にあります。") == "寝室")
    }

    /// About 1% of sentences never spell their headword. No highlight is the
    /// right answer there — quieter than a wrong one.
    @Test
    func aSentenceThatNeverNamesTheWordGetsNoHighlight() {
        #expect(self.marked("scanner", "Scan both sides of the document.") == nil)
        #expect(self.marked("ベッド", "私は夜11時に寝ます。") == nil)
    }

    @Test
    func anEmptyWordOrSentenceIsRefusedRatherThanMatchingEverything() {
        #expect(self.marked("", "The fork is here.") == nil)
        #expect(self.marked("fork", "") == nil)
    }

    // MARK: - Rating

    private func listeningCoordinator(
        audio: FakeSpeechPlaying,
        writer: ListenAnswerSpy
    ) throws
        -> ReviewFlowCoordinator
    {
        // Only 聽句's own word in the queue, so `upcomingWordIds` cannot eat the
        // whole distractor pool.
        let queue = try [makeQueue()[0]]
        return ReviewFlowCoordinator(
            queue: queue,
            writer: writer,
            queueProvider: EmptyQueueProvider(),
            audio: audio,
            beat: { _ in }
        )
    }

    /// The rule ADR-0014 exists for: at two options a fast correct answer is a
    /// coin flip, so it must not take the path that writes 熟練 with no sheet.
    @Test
    func aFastCorrectListeningAnswerStillRaisesTheSheet() async throws {
        let audio = FakeSpeechPlaying()
        let spy = ListenAnswerSpy()
        let coord = try self.listeningCoordinator(audio: audio, writer: spy)
        await coord.prepareQuestion(pool: self.pool(), session: .en, online: true, voice: .us)
        try #require(coord.question?.kind == .hearSentence)

        let answer = try #require(coord.question?.imageOptions?.first { $0.id == "w-mug" })
        coord.pickImage(answer)

        #expect(coord.question?.wasCorrect == true)
        #expect(coord.flash == nil, "a two-option answer must not flash-advance")
        try await self.awaitReveal(coord)
        #expect(coord.revealMode == .rate)
    }

    /// 看圖選字 rules a wrong option out and keeps the question open. 聽句 must
    /// not: with two pictures, ruling one out *is* answering — the same 50%
    /// that keeps it off the auto-rate path (ADR-0014).
    @Test
    func aWrongListeningAnswerStillResolvesOnTheFirstTap() async throws {
        let audio = FakeSpeechPlaying()
        let coord = try self.listeningCoordinator(audio: audio, writer: ListenAnswerSpy())
        await coord.prepareQuestion(pool: self.pool(), session: .en, online: true, voice: .us)
        try #require(coord.question?.kind == .hearSentence)

        let distractor = try #require(coord.question?.imageOptions?.first { $0.id != "w-mug" })
        coord.pickImage(distractor)

        #expect(coord.question?.wasCorrect == false)
        #expect(coord.question?.phase == .review)
        try await self.awaitReveal(coord)
        #expect(coord.revealMode == .rate)
        #expect(coord.question?.wrongPicks.isEmpty == true, "聽句 never rules options out")
    }

    @Test
    func theClockOnlyStartsWhenTheSentenceEnds() async throws {
        let audio = FakeSpeechPlaying()
        audio.holdsPlayback = true
        let coord = try self.listeningCoordinator(audio: audio, writer: ListenAnswerSpy())

        let prepare = Task { await coord.prepareQuestion(
            pool: self.pool(), session: .en, online: true, voice: .us
        ) }
        try await self.waitUntil { audio.isHolding }
        #expect(coord.question?.awaitingAudio == true, "the clock must not run while the sentence plays")

        audio.release()
        await prepare.value
        #expect(coord.question?.awaitingAudio == false)
    }

    /// Replays spend time on purpose — needing three listens *is* 困難 — so the
    /// button must not double as a way to reset the stopwatch.
    @Test
    func aReplayDoesNotResetTheClock() async throws {
        let audio = FakeSpeechPlaying()
        let coord = try self.listeningCoordinator(audio: audio, writer: ListenAnswerSpy())
        await coord.prepareQuestion(pool: self.pool(), session: .en, online: true, voice: .us)
        let started = try #require(coord.question?.startedAt)

        await coord.replaySentence()
        #expect(coord.question?.startedAt == started)
        #expect(coord.question?.replayCount == 1)
    }

    /// The defect: the adapter reported a play cut off by a replay as
    /// `.failed`, so replaying before the first play ended marked the audio
    /// failed and started the clock at the replay tap.
    @Test
    func replayingBeforeTheFirstPlayEndsIsNotAnAudioFailure() async throws {
        let audio = FakeSpeechPlaying()
        audio.holdsPlayback = true
        let times = Clock(Date(timeIntervalSince1970: 1000))
        let queue = try [makeQueue()[0]]
        let coord = ReviewFlowCoordinator(
            queue: queue,
            writer: ListenAnswerSpy(),
            queueProvider: EmptyQueueProvider(),
            audio: audio,
            beat: { _ in },
            now: { times.now }
        )
        let first = Task { await coord.prepareQuestion(pool: self.pool(), session: .en, online: true, voice: .us) }
        try await self.waitUntil { audio.isHolding }

        times.now = Date(timeIntervalSince1970: 1002)
        let replay = Task { await coord.replaySentence() }
        await first.value
        #expect(coord.question?.audioFailed == false, "a play the user cut off by replaying did not fail")
        #expect(coord.question?.awaitingAudio == true, "the clock waits for the sentence the user is hearing")

        times.now = Date(timeIntervalSince1970: 1005)
        try await self.waitUntil { audio.isHolding }
        audio.release(.finished)
        await replay.value

        #expect(coord.question?.audioFailed == false)
        #expect(coord.question?.awaitingAudio == false)
        #expect(coord.question?.startedAt == Date(timeIntervalSince1970: 1005))
        #expect(coord.question?.replayCount == 1)
    }

    /// ADR-0014: 「超過 3 秒還沒開始播，碼表直接起算並標 audioFailed」. It had
    /// no code, so a clip stuck downloading left the clock waiting forever.
    @Test
    func aFirstPlayThatNeverStartsStartsTheClockAndMarksTheAudio() async throws {
        let audio = FakeSpeechPlaying()
        audio.holdsPlayback = true
        audio.startsImmediately = false
        let coord = try self.listeningCoordinator(audio: audio, writer: ListenAnswerSpy())

        let prepare = Task { await coord.prepareQuestion(pool: self.pool(), session: .en, online: true, voice: .us) }
        // Held first: before the question is presented `awaitingAudio` is false
        // too, and waiting on it alone returns before anything has played.
        try await self.waitUntil { audio.isHolding }
        try await self.waitUntil { coord.question?.awaitingAudio == false }

        #expect(coord.question?.audioFailed == true)
        audio.release(.stopped)
        await prepare.value
    }

    @Test
    func aFirstPlayThatStartedIsNotTimedOut() async throws {
        let audio = FakeSpeechPlaying()
        audio.holdsPlayback = true
        let coord = try self.listeningCoordinator(audio: audio, writer: ListenAnswerSpy())

        let prepare = Task { await coord.prepareQuestion(pool: self.pool(), session: .en, online: true, voice: .us) }
        try await self.waitUntil { audio.isHolding }
        for _ in 0..<20 {
            await Task.yield()
        }

        #expect(coord.question?.awaitingAudio == true, "a long sentence still playing must keep the clock waiting")
        #expect(coord.question?.audioFailed == false)
        audio.release(.finished)
        await prepare.value
    }

    /// Reaching for 慢讀 says the sentence did not land at speed — the same
    /// thing pressing play again says — so it counts as a replay. And like any
    /// replay it must not restart the clock, or the button becomes a way to buy
    /// time (ADR-0014).
    @Test
    func slowPlaybackIsAReplayAndDoesNotResetTheClock() async throws {
        let audio = FakeSpeechPlaying()
        let coord = try self.listeningCoordinator(audio: audio, writer: ListenAnswerSpy())
        await coord.prepareQuestion(pool: self.pool(), session: .en, online: true, voice: .us)
        let started = try #require(coord.question?.startedAt)

        await coord.replaySentence(slow: true)

        #expect(coord.question?.replayCount == 1)
        #expect(coord.question?.startedAt == started)
        #expect(audio.rates.last == ReviewFlowCoordinator.slowRate)
    }

    @Test
    func theAutomaticFirstPlayIsAlwaysFullSpeed() async throws {
        let audio = FakeSpeechPlaying()
        let coord = try self.listeningCoordinator(audio: audio, writer: ListenAnswerSpy())
        await coord.prepareQuestion(pool: self.pool(), session: .en, online: true, voice: .us)
        #expect(audio.rates == [1])
        #expect(coord.question?.replayCount == 0, "the card playing itself is not the user asking again")
    }

    /// The play button used to resolve the voice again from settings at each
    /// tap, a third copy of the lookup the first play had already done. A
    /// replay now reads the voice the question was decided with.
    @Test
    func aReplayIsTheSameRecordingAsTheFirstPlay() async throws {
        let audio = FakeSpeechPlaying()
        let coord = try self.listeningCoordinator(audio: audio, writer: ListenAnswerSpy())
        await coord.prepareQuestion(pool: self.pool(), session: .en, online: true, voice: .us)
        await coord.replaySentence(slow: true)
        #expect(audio.voices == [.us, .us])
        #expect(audio.plays.count == 2)
        #expect(Set(audio.plays).count == 1)
    }

    @Test
    func aNormalReplayStaysAtFullSpeed() async throws {
        let audio = FakeSpeechPlaying()
        let coord = try self.listeningCoordinator(audio: audio, writer: ListenAnswerSpy())
        await coord.prepareQuestion(pool: self.pool(), session: .en, online: true, voice: .us)
        await coord.replaySentence()
        #expect(audio.rates.last == 1)
    }

    // MARK: - 這輪不做聽句題

    /// Someone presses this *because* they cannot answer the card in front of
    /// them, so leaving that card as a listening question would be answering a
    /// question they just said they cannot hear.
    @Test
    func optingOutConvertsTheCardInFrontOfYouToo() async throws {
        let audio = FakeSpeechPlaying()
        let coord = try self.listeningCoordinator(audio: audio, writer: ListenAnswerSpy())
        await coord.prepareQuestion(pool: self.pool(), session: .en, online: true, voice: .us)
        try #require(coord.question?.kind == .hearSentence)

        coord.optOutOfListening()

        #expect(coord.question?.kind == .pickWord)
        #expect(coord.question?.imageOptions == nil)
        #expect(coord.question?.example == nil)
        #expect(audio.stopped == 1, "the sentence must not keep playing")
    }

    @Test
    func optingOutSilencesTheRestOfTheSession() async throws {
        let audio = FakeSpeechPlaying()
        let coord = try self.listeningCoordinator(audio: audio, writer: ListenAnswerSpy())
        await coord.prepareQuestion(pool: self.pool(), session: .en, online: true, voice: .us)
        coord.optOutOfListening()

        // The same card, prepared again, must not come back as 聽句.
        await coord.prepareQuestion(pool: self.pool(), session: .en, online: true, voice: .us)
        #expect(coord.question?.kind == .pickWord)
    }

    /// No answer was revealed, so nothing is owed. This is the one place the
    /// distinction matters: the eye and this button are both "I am stuck", but
    /// only one of them shows you the answer.
    @Test
    func optingOutIsNotAHint() async throws {
        let audio = FakeSpeechPlaying()
        let coord = try self.listeningCoordinator(audio: audio, writer: ListenAnswerSpy())
        await coord.prepareQuestion(pool: self.pool(), session: .en, online: true, voice: .us)
        coord.optOutOfListening()
        #expect(coord.question?.hinted == false)

        // Assert it through the thing that actually consumes `hinted`: answer
        // correctly and check the full positive table is still on offer. The
        // earlier version of this test compared `availableRatings` before
        // answering, which passes whatever `hinted` says.
        coord.pick("mug")
        #expect(coord.question?.wasCorrect == true)
        #expect(coord.question?.availableRatings == [.hard, .good, .easy])
    }

    /// The card is now a different question, so its clock starts now — and the
    /// listening-only metadata must stop being sent with it.
    @Test
    func optingOutRestartsTheClockAndDropsListeningMetadata() async throws {
        let audio = FakeSpeechPlaying()
        let spy = ListenAnswerSpy()
        let coord = try self.listeningCoordinator(audio: audio, writer: spy)
        await coord.prepareQuestion(pool: self.pool(), session: .en, online: true, voice: .us)
        await coord.replaySentence()
        let before = try #require(coord.question?.startedAt)

        coord.optOutOfListening()
        let after = try #require(coord.question?.startedAt)
        #expect(after > before)

        coord.pick("mug")
        coord.rate(.good)
        try await self.waitUntil { spy.answers.isEmpty == false }
        let payload = try #require(spy.answers.first)
        #expect(payload.activity == "mcq")
        #expect(payload.replayCount == nil, "a 選字 row must not claim replays of audio")
        #expect(payload.audioFailed == nil)
        // But the fact that this card *was* a listening question has to survive
        // somewhere: `activity` truthfully says mcq, so this is the only place.
        #expect(payload.convertedFromListening == true)
        #expect(payload.listeningOptedOut == true)
    }

    /// The rest of the session answers as 選字, and those rows must stay
    /// distinguishable from a session that never met a listening question —
    /// otherwise an aggregate listening accuracy is computed over a population
    /// that quietly selected itself.
    @Test
    func everyLaterAnswerInTheSessionCarriesTheOptOut() async throws {
        let audio = FakeSpeechPlaying()
        let spy = ListenAnswerSpy()
        let coord = try ReviewFlowCoordinator(
            queue: makeQueue(),
            writer: spy,
            queueProvider: EmptyQueueProvider(),
            audio: audio,
            beat: { _ in }
        )
        // A wider pool than `pool()`: with both queue items present, `w-cup` is
        // excluded as still-queued and `w-plate` as named by the sentence, so
        // the shared pool has no distractor left and the card would quietly
        // demote to 選字 — leaving nothing to opt out of.
        let wide = self.pool() + [
            CardWord(
                id: "w-bowl", word: "bowl", chinese: "碗",
                imageUrl: "https://x/bowl.webp", category: "kitchen",
                pronunciation: "", targetLanguage: .en
            )
        ]
        await coord.prepareQuestion(pool: wide, session: .en, online: true, voice: .us)
        try #require(coord.question?.kind == .hearSentence)
        coord.optOutOfListening()
        coord.pick("mug")
        coord.rate(.good)
        try await self.waitUntil { coord.index == 1 }

        await coord.prepareQuestion(pool: wide, session: .en, online: true, voice: .us)
        coord.pick("cup")
        coord.rate(.good)
        try await self.waitUntil { spy.answers.count == 2 }

        let second = try #require(spy.answers.last)
        #expect(second.listeningOptedOut == true, "the session is still opted out")
        #expect(
            second.convertedFromListening == nil,
            "only the card they bailed on carries this"
        )
    }

    /// Absent rather than `false`: a 選字 row in an ordinary session should not
    /// claim anything about a feature it never met.
    @Test
    func anOrdinarySessionSendsNeitherFlag() async throws {
        let audio = FakeSpeechPlaying()
        let spy = ListenAnswerSpy()
        let coord = try self.listeningCoordinator(audio: audio, writer: spy)
        await coord.prepareQuestion(pool: self.pool(), session: .en, online: false, voice: .us)
        coord.pick("mug")
        coord.rate(.good)
        try await self.waitUntil { spy.answers.isEmpty == false }

        let payload = try #require(spy.answers.first)
        #expect(payload.listeningOptedOut == nil)
        #expect(payload.convertedFromListening == nil)
    }

    @Test
    func optingOutDoesNothingOnAPickWordCard() async throws {
        let audio = FakeSpeechPlaying()
        let coord = try self.listeningCoordinator(audio: audio, writer: ListenAnswerSpy())
        await coord.prepareQuestion(pool: self.pool(), session: .en, online: false, voice: .us)
        try #require(coord.question?.kind == .pickWord)

        coord.optOutOfListening()
        #expect(!coord.listeningOptedOut, "nothing to opt out of")
    }

    @Test
    func liftingTheBlurCostsTheSameAsTheHintFlip() async throws {
        let audio = FakeSpeechPlaying()
        let coord = try self.listeningCoordinator(audio: audio, writer: ListenAnswerSpy())
        await coord.prepareQuestion(pool: self.pool(), session: .en, online: true, voice: .us)

        coord.revealSentence()
        #expect(coord.question?.sentenceRevealed == true)
        #expect(coord.question?.hinted == true)

        let answer = try #require(coord.question?.imageOptions?.first { $0.id == "w-mug" })
        coord.pickImage(answer)
        #expect(coord.question?.availableRatings == [.again, .hard], "a read answer cannot claim 穩定")
    }

    @Test
    func thePayloadCarriesListeningAndItsMetadata() async throws {
        let audio = FakeSpeechPlaying()
        audio.outcome = .fallback
        let spy = ListenAnswerSpy()
        let coord = try self.listeningCoordinator(audio: audio, writer: spy)
        await coord.prepareQuestion(pool: self.pool(), session: .en, online: true, voice: .us)
        await coord.replaySentence()

        let answer = try #require(coord.question?.imageOptions?.first { $0.id == "w-mug" })
        coord.pickImage(answer)
        try await self.awaitReveal(coord)
        coord.rate(.good)
        try await self.waitUntil { spy.answers.isEmpty == false }

        let payload = try #require(spy.answers.first)
        #expect(payload.activity == "listening")
        #expect(payload.replayCount == 1)
        #expect(payload.audioFailed == true, "synthesized audio is not evidence about listening")
    }

    /// Offline with nothing cached, the fallback inside `SpeechService` is
    /// on-device synthesis of a sentence whose readings nothing can correct.
    /// That card takes 選字 rather than a question it cannot ask honestly.
    @Test
    func offlineFallsBackToPickWord() async throws {
        let audio = FakeSpeechPlaying()
        let coord = try self.listeningCoordinator(audio: audio, writer: ListenAnswerSpy())
        await coord.prepareQuestion(pool: self.pool(), session: .en, online: false, voice: .us)

        #expect(coord.question?.kind == .pickWord)
        #expect(coord.question?.imageOptions == nil)
        #expect(audio.plays.isEmpty)
    }

    @Test
    func aListeningCardDoesNotOfferTheEightSecondNudge() async throws {
        let audio = FakeSpeechPlaying()
        let coord = try self.listeningCoordinator(audio: audio, writer: ListenAnswerSpy())
        await coord.prepareQuestion(pool: self.pool(), session: .en, online: true, voice: .us)
        #expect(coord.question?.canNudge == false)
    }

    /// The view draws a skeleton until this flips. `kind` defaults to
    /// `.pickWord`, whose hero is the answer's own picture — so a card that
    /// renders before the decision lands shows the answer to what turns out to
    /// be a listening question.
    @Test
    func nothingIsDrawnBeforeTheQuestionIsDecided() async throws {
        let audio = FakeSpeechPlaying()
        audio.holdsPlayback = true
        let coord = try self.listeningCoordinator(audio: audio, writer: ListenAnswerSpy())
        #expect(coord.question?.ready == false)

        let prepare = Task { await coord.prepareQuestion(
            pool: self.pool(), session: .en, online: true, voice: .us
        ) }
        // Ready before the audio finishes: the card is answerable while the
        // sentence plays, only the clock waits.
        try await self.waitUntil { coord.question?.ready == true }
        #expect(coord.question?.kind == .hearSentence)
        try await self.waitUntil { audio.isHolding }
        audio.release()
        await prepare.value
    }

    @Test
    func aPickWordCardIsAlsoMarkedReady() async throws {
        let audio = FakeSpeechPlaying()
        let coord = try self.listeningCoordinator(audio: audio, writer: ListenAnswerSpy())
        await coord.prepareQuestion(pool: self.pool(), session: .en, online: false, voice: .us)
        #expect(coord.question?.kind == .pickWord)
        #expect(coord.question?.ready == true, "a 選字 card must not sit behind the skeleton forever")
    }

    /// `awaitTerminal` is built on `withCheckedContinuation`, which ignores
    /// task cancellation — so cancelling the view's `.task` does not reach the
    /// audio, and leaving has to say so explicitly.
    @Test
    func leavingStopsTheSentence() async throws {
        let audio = FakeSpeechPlaying()
        let coord = try self.listeningCoordinator(audio: audio, writer: ListenAnswerSpy())
        await coord.prepareQuestion(pool: self.pool(), session: .en, online: true, voice: .us)
        try #require(coord.question?.kind == .hearSentence)

        coord.cancelPendingBeats()
        #expect(audio.stopped == 1)
    }
}

// Local doubles: the equivalents in `ReviewFlowCoordinatorTests` are
// file-private, and widening them to share would make every future edit to one
// suite a question about the other.

@MainActor
private final class ListenAnswerSpy: DurableAnswerWriting {
    private(set) var answers: [StudyAnswerPayload] = []

    func submitAnswer(_ payload: StudyAnswerPayload) async -> StudyWriteOutcome {
        self.answers.append(payload)
        return .synced(StudyAnswerResponse(ok: true, milestone: nil, mastery: nil))
    }
}

@MainActor
private final class EmptyQueueProvider: StudyQueueProviding {
    func fetch(mode _: StudyMode) async throws -> [StudyQueueItem] {
        []
    }

    func take(mode _: StudyMode) -> [StudyQueueItem]? {
        nil
    }
}

@MainActor
private final class Clock {
    var now: Date

    init(_ now: Date) {
        self.now = now
    }
}
