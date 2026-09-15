// One 聽句 question's audio: which request is the question's own, when the
// clock may start, and what counts against the listening evidence.
//
// These rules were spread across six files — the replay button, the voice in
// the view, `playSentence` on the coordinator, three mutators on
// `ReviewQuestion`, the observation bridge, and `SpeechService` — and three
// of them were wrong in ways no test could reach:
//
//   • Replaying before the first play ended cut the first play off, and the
//     adapter reported a cut-off request as `.failed`. So the first play
//     "failed": `audioFailed` was set, and the clock started at the replay tap,
//     not when the audio the user was actually hearing ended.
//   • Replays after answering were counted. The payload is built at the rating,
//     after the sheet, so listening to the sentence again *while reading the
//     answer* was sent as 「needed three listens」.
//   • ADR-0014's 「超過 3 秒還沒開始播，碼表直接起算並標 audioFailed」 had no code.
//
// Pure: no audio, no timers. The coordinator plays, schedules, and reports what
// happened; this decides what it means.

import Foundation

struct SentencePlayback: Equatable {
    /// The clock waits for the first audio the user hears to end.
    private(set) var awaitingClock: Bool
    /// Whether this question's sentence is playing right now, for the button.
    private(set) var isPlaying = false
    /// The clip was unreachable (on-device synthesis read it), nothing came
    /// out, or nothing started within the timeout.
    private(set) var audioFailed = false
    /// Replays asked for before answering.
    private(set) var replayCount = 0

    /// The newest request this question made. An outcome for any older one
    /// belongs to a play the question itself replaced, and is not news.
    private var latest = 0
    private var anyStarted = false

    init(awaitsClock: Bool) {
        self.awaitingClock = awaitsClock
    }

    /// A play is about to start. Returns the token its outcome must carry.
    ///
    /// - Parameter countsAsReplay: the user asked again, before answering.
    mutating func begin(countsAsReplay: Bool) -> Int {
        self.latest += 1
        self.isPlaying = true
        if countsAsReplay { self.replayCount += 1 }
        return self.latest
    }

    /// Sound came out for `token`.
    mutating func started(_ token: Int) {
        guard token == self.latest else { return }
        self.anyStarted = true
    }

    /// A play ended. Returns true when the clock should start now.
    mutating func ended(_ token: Int, _ outcome: SpeechPlayback) -> Bool {
        // Replaced by this question's own newer request: that one will end,
        // and it is what the user is hearing.
        guard token == self.latest else { return false }
        self.isPlaying = false
        switch outcome {
        case .finished:
            break
        case .fallback, .failed:
            self.audioFailed = true
        case .superseded, .stopped:
            // Something else took the speaker — a pronunciation button, or
            // leaving. The sentence was cut off, not broken.
            break
        }
        return self.startClock()
    }

    /// The timeout after the first play began. Returns true when the clock
    /// should start now: nothing has started, so the answer is not evidence
    /// about listening (ADR-0014).
    mutating func startTimedOut() -> Bool {
        guard self.awaitingClock, !self.anyStarted else { return false }
        self.audioFailed = true
        return self.startClock()
    }

    /// The question stopped being a listening question.
    mutating func abandon() {
        self.isPlaying = false
        self.awaitingClock = false
    }

    private mutating func startClock() -> Bool {
        guard self.awaitingClock else { return false }
        self.awaitingClock = false
        return true
    }
}
