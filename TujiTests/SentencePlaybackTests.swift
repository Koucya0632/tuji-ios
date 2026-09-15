import Testing
@testable import Tuji

/// One 聽句 question's audio — see `SentencePlayback`.
///
/// Every mutating call is stored before it is asserted: `#expect` cannot wrap
/// one, and the error points at the generated macro file.
struct SentencePlaybackTests {
    @Test
    func theClockStartsWhenTheFirstPlayEnds() {
        var playback = SentencePlayback(awaitsClock: true)
        let token = playback.begin(countsAsReplay: false)
        playback.started(token)

        let startsClock = playback.ended(token, .finished)

        #expect(startsClock)
        #expect(!playback.awaitingClock)
        #expect(!playback.audioFailed)
    }

    /// A replay cut the first play off. Its `.superseded` is not news; the
    /// replay's end is when the audio the user heard ended.
    @Test
    func aPlayReplacedByThisQuestionsOwnReplayIsIgnored() {
        var playback = SentencePlayback(awaitsClock: true)
        let first = playback.begin(countsAsReplay: false)
        let replay = playback.begin(countsAsReplay: true)

        let firstStartsClock = playback.ended(first, .superseded)
        #expect(!firstStartsClock)
        #expect(playback.awaitingClock)
        #expect(playback.isPlaying)

        let replayStartsClock = playback.ended(replay, .finished)
        #expect(replayStartsClock)
        #expect(!playback.audioFailed)
    }

    /// Something outside the question took the speaker — a pronunciation button
    /// in the reveal sheet. The sentence was cut off, not broken.
    @Test
    func aPlayCutOffFromOutsideIsNotAFailure() {
        var playback = SentencePlayback(awaitsClock: true)
        let token = playback.begin(countsAsReplay: false)

        let startsClock = playback.ended(token, .superseded)

        #expect(startsClock)
        #expect(!playback.audioFailed)
        #expect(!playback.isPlaying)
    }

    @Test
    func stoppingIsNotAFailure() {
        var playback = SentencePlayback(awaitsClock: false)
        let token = playback.begin(countsAsReplay: false)

        let startsClock = playback.ended(token, .stopped)

        #expect(!startsClock)
        #expect(!playback.audioFailed)
    }

    @Test(arguments: [SpeechPlayback.fallback, .failed])
    func aFallbackOrFailureMarksTheAudio(outcome: SpeechPlayback) {
        var playback = SentencePlayback(awaitsClock: true)
        let token = playback.begin(countsAsReplay: false)

        let startsClock = playback.ended(token, outcome)

        #expect(startsClock)
        #expect(playback.audioFailed)
    }

    /// ADR-0014: nothing has started by the timeout.
    @Test
    func aTimeoutBeforeAnythingStartsMarksTheAudioAndStartsTheClock() {
        var playback = SentencePlayback(awaitsClock: true)
        _ = playback.begin(countsAsReplay: false)

        let startsClock = playback.startTimedOut()

        #expect(startsClock)
        #expect(playback.audioFailed)
        #expect(!playback.awaitingClock)
    }

    @Test
    func aTimeoutAfterSoundStartedChangesNothing() {
        var playback = SentencePlayback(awaitsClock: true)
        let token = playback.begin(countsAsReplay: false)
        playback.started(token)

        let startsClock = playback.startTimedOut()

        #expect(!startsClock)
        #expect(!playback.audioFailed)
        #expect(playback.awaitingClock, "a long sentence still playing keeps the clock waiting")
    }

    @Test
    func onlyReplaysThatCountAreCounted() {
        var playback = SentencePlayback(awaitsClock: false)
        _ = playback.begin(countsAsReplay: false)
        _ = playback.begin(countsAsReplay: true)
        _ = playback.begin(countsAsReplay: false)
        #expect(playback.replayCount == 1)
    }
}
