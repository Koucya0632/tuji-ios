// 聽句's one reach into the world: can this sentence be played right now, and
// tell me when it has finished.
//
// It is a seam rather than a `SpeechService.shared` call inside the coordinator
// because the coordinator's clock hangs off the answer — "started" is when the
// audio *ended* (ADR-0014) — and a rule that only fires after a real 2-second
// clip is a rule no test can reach. The `async` shape is the point: awaiting is
// what the coordinator actually wants to express, and a fake satisfies it in a
// single line.
//
// `SpeechService` publishes state rather than taking a completion handler, so
// the adapter below is where the two shapes meet. That asymmetry is deliberate:
// `PronunciationButton` wants the state (to tint its ground while a clip
// plays) and this wants the event, and building the service around this one
// caller's shape is how a module ends up unusable by the next one.

import Foundation
import Observation

/// How a sentence's audio ended.
enum ListeningPlayback: Equatable {
    /// The pre-generated clip played to its end.
    case finished
    /// No clip, so this was on-device synthesis. Recorded as `audioFailed`:
    /// the sentence was read aloud, but by a reading nothing can correct, so
    /// the answer is not evidence about listening either way.
    case fallback
    /// Nothing came out.
    case failed
}

@MainActor
protocol ListeningAudio {
    /// Whether this clip plays with no network — cached on disk, or a live
    /// connection to fetch it. False sends the card to 選字 instead.
    func canPlay(_ urlString: String?, online: Bool) -> Bool

    /// Play, and return when the audio ends.
    func play(_ urlString: String?, text: String, voice: SpeechService.Voice) async -> ListeningPlayback
}

/// The real one: `SpeechService` for playback and the on-disk clip cache.
@MainActor
struct LiveListeningAudio: ListeningAudio {
    var speech: SpeechService = .shared

    func canPlay(_ urlString: String?, online: Bool) -> Bool {
        guard let urlString, !urlString.isEmpty else { return false }
        // Cached beats connected: a clip already on disk plays on a plane.
        return self.speech.hasCachedClip(for: urlString) || online
    }

    func play(
        _ urlString: String?,
        text: String,
        voice: SpeechService.Voice
    ) async
        -> ListeningPlayback
    {
        let request = self.speech.play(urlString: urlString, fallbackText: text, voice: voice)
        return await self.awaitTerminal(request)
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
    private func awaitTerminal(_ request: Int) async -> ListeningPlayback {
        let speech = self.speech
        while true {
            var terminal: ListeningPlayback?
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                let box = ResumeOnce(continuation)
                withObservationTracking {
                    terminal = Self.terminal(speech.playback, request: request)
                } onChange: {
                    box.resume()
                }
                if terminal != nil { box.resume() }
            }
            if let terminal { return terminal }
        }
    }

    /// The outcome this state settles, or nil while it is still going.
    private static func terminal(
        _ state: SpeechService.PlaybackState?,
        request: Int
    )
        -> ListeningPlayback?
    {
        guard let state else { return nil }
        // A newer request superseded ours. It will never reach a terminal phase
        // now, so stop waiting for one — the card that asked has moved on.
        guard state.requestID == request else { return .failed }
        switch state.phase {
        case .finished: return state.usedFallback ? .fallback : .finished
        case .failed: return .failed
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
