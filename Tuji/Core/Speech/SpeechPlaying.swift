// Playing a recording, and being told when it has ended.
//
// A seam rather than a `SpeechService.shared` call inside the caller, because
// 聽句's clock hangs off the answer — "started" is when the audio *ended*
// (ADR-0014) — and a rule that only fires after a real 2-second clip is a rule
// no test can reach. The `async` shape is the point: awaiting is what a caller
// actually wants to express, and a fake satisfies it in a single line.
//
// It was `ListeningAudio`, in `Core/Study`, and it had one caller. **A module
// named after one of its callers does not get found by the next one** — the
// lesson `ImageIntake` learned from `AvatarPicker` and `TileBoard` from
// `NewFlowCoordinator`. Nothing here was ever specific to 聽句.
//
// `SpeechService` publishes state rather than taking a completion handler, so
// the adapter below is where the two shapes meet. That asymmetry is deliberate:
// `PronunciationButton` wants the state (to tint its ground while a clip
// plays) and this wants the event, and building the service around either one
// caller's shape is how a module ends up unusable by the other.

import Foundation
import Observation

/// How a sentence's audio ended.
enum SpeechPlayback: Equatable {
    /// The pre-generated clip played to its end.
    case finished
    /// No clip, so this was on-device synthesis. Recorded as `audioFailed`:
    /// the sentence was read aloud, but by a reading nothing can correct, so
    /// the answer is not evidence about listening either way.
    case fallback
    /// Nothing came out.
    case failed
    /// A newer request took the speaker before this one ended. Not a failure:
    /// the audio that replaced it may be this question's own replay.
    case superseded
    /// `stop()` cut it off.
    case stopped
}

@MainActor
protocol SpeechPlaying {
    /// Whether this clip plays with no network — cached on disk, or a live
    /// connection to fetch it. False sends the card to 選字 instead.
    func canPlay(_ urlString: String?, online: Bool) -> Bool

    /// Play, and return when the audio ends. `rate` is a multiplier on normal
    /// speed — 慢讀 passes 0.8. `onStart` runs once, when sound comes out: a
    /// clip still downloading has not started, and ADR-0014 times out on that.
    func play(
        _ urlString: String?,
        text: String,
        voice: SpeechService.Voice,
        rate: Float,
        onStart: @escaping @MainActor () -> Void
    ) async
        -> SpeechPlayback

    /// Cut playback off. Leaving 複習 mid-sentence must not narrate the screen
    /// the user went to instead — and 聽句 auto-plays, so unlike the
    /// pronunciation button this is audio nobody asked to start.
    func stop()
}

/// The real one: `SpeechService` for playback and the on-disk clip cache.
@MainActor
struct LiveSpeechPlaying: SpeechPlaying {
    var speech: SpeechService = .shared

    func canPlay(_ urlString: String?, online: Bool) -> Bool {
        guard let urlString, !urlString.isEmpty else { return false }
        // Cached beats connected: a clip already on disk plays on a plane.
        return self.speech.hasCachedClip(for: urlString) || online
    }

    func stop() {
        self.speech.stop()
    }

    func play(
        _ urlString: String?,
        text: String,
        voice: SpeechService.Voice,
        rate: Float,
        onStart: @escaping @MainActor () -> Void
    ) async
        -> SpeechPlayback
    {
        let request = self.speech.play(
            urlString: urlString,
            fallbackText: text,
            voice: voice,
            rate: rate
        )
        return await self.awaitTerminal(request, onStart: onStart)
    }

    /// Bridges the observable state back to one `await`.
    ///
    /// `withObservationTracking` reports a change once and has to be re-armed,
    /// so this loops. Two things about the shape are load-bearing:
    ///
    /// **The read and the arming happen in the same synchronous block.** Read
    /// the state first and arm afterwards and there is a gap: a change landing
    /// in it is never reported, and the caller waits for a finish that already
    /// happened. So the terminal check runs *inside* the tracked block, and the
    /// continuation resumes immediately when it is already terminal.
    ///
    /// **The loop is iterative, not a recursive local `arm()`.** `onChange` is
    /// `@Sendable`, and a local function captured by one is a non-Sendable
    /// capture — accepted by the Debug build and rejected outright by the
    /// whole-module release build. The only thing this closure captures is the
    /// `Sendable` box.
    private func awaitTerminal(
        _ request: Int,
        onStart: @MainActor () -> Void
    ) async
        -> SpeechPlayback
    {
        let speech = self.speech
        var reportedStart = false
        while true {
            var terminal: SpeechPlayback?
            var playing = false
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                let box = ResumeOnce(continuation)
                withObservationTracking {
                    terminal = Self.terminal(speech.playback, request: request)
                    playing = speech.playback?.requestID == request && speech.playback?.phase == .playing
                } onChange: {
                    box.resume()
                }
                if terminal != nil || (playing && !reportedStart) { box.resume() }
            }
            if playing, !reportedStart {
                reportedStart = true
                onStart()
            }
            if let terminal { return terminal }
        }
    }

    /// The outcome this state settles, or nil while it is still going.
    private static func terminal(
        _ state: SpeechService.PlaybackState?,
        request: Int
    )
        -> SpeechPlayback?
    {
        guard let state else { return nil }
        // A newer request superseded ours. It will never reach a terminal phase
        // now, so stop waiting for one. `.superseded`, not `.failed`: a replay
        // superseding its own first play is the most common way this happens.
        guard state.requestID == request else { return .superseded }
        switch state.phase {
        case .finished: return state.usedFallback ? .fallback : .finished
        case .failed: return .failed
        case .stopped: return .stopped
        case .loading, .playing: return nil
        }
    }
}

/// One-shot continuation guard, `Sendable` because `onChange` is.
///
/// It can be signalled twice — once by the tracking callback and once by the
/// already-terminal check above, racing — and resuming a continuation twice
/// traps rather than warns.
///
/// Explicitly `nonisolated`: the target builds with
/// `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, so a plain type here would be
/// main-actor-isolated and unreachable from the `@Sendable` `onChange`.
private final nonisolated class ResumeOnce: Sendable {
    private let lock = NSLock()
    private nonisolated(unsafe) var continuation: CheckedContinuation<Void, Never>?

    init(_ continuation: CheckedContinuation<Void, Never>) {
        self.continuation = continuation
    }

    func resume() {
        self.lock.lock()
        let pending = self.continuation
        self.continuation = nil
        self.lock.unlock()
        pending?.resume()
    }
}
