// 語音輸入 — speech into a draft. Hands back the running transcript while the
// person talks; what to do with it is the caller's. Nothing is recorded or kept.
//
// Apple's recogniser, on the device whenever the language allows it, as for
// 跟讀 (`ShadowingRecorder`). One language at a time: the recogniser listens for
// one locale, so switching language starts again. The mic and recogniser are
// `SpeechListening`'s; this keeps the timing.
//
// It stops by itself after a pause once something has been heard, after a
// longer wait if nothing ever was, at a hard ceiling, and when the system takes
// the mic away (a call, the route changing); `stop` ends it too. `cancel` drops
// it, and anything the recogniser says afterwards is ignored — for when the
// draft is about to be sent or typed into.

import Foundation
import Observation

@MainActor
@Observable
final class Dictation {
    enum Phase: Equatable {
        case idle
        case listening
        /// Microphone or speech recognition was refused.
        case denied
        /// No recogniser for this language on this device.
        case unavailable
        /// The recogniser exists but can't be reached now: a language that
        /// only runs on Apple's servers, with no network.
        case offline
        case failed
    }

    private(set) var phase: Phase = .idle
    /// The language being listened for, while listening or after a problem.
    private(set) var locale: Locale?

    @ObservationIgnored private let input: SpeechListening
    @ObservationIgnored private let sleep: SpeechSleep
    @ObservationIgnored private var timer: Task<Void, Never>?
    @ObservationIgnored private var ceiling: Task<Void, Never>?
    @ObservationIgnored private var heard: (String) -> Void = { _ in }
    /// Bumped on every start and cancel so a late callback from an earlier try is ignored.
    @ObservationIgnored private var attempt = 0

    /// Stop after this long without a new word, once something was heard —
    /// longer than 跟讀's, because the person is thinking of what to say, not reading.
    static let pause: Duration = .seconds(3)
    /// Give up after this long if nothing is heard at all.
    static let silence: Duration = .seconds(8)
    /// Never listen longer than this.
    static let maximum: Duration = .seconds(60)

    init(
        input: SpeechListening = LiveSpeechInput(category: "dictation"),
        sleep: @escaping SpeechSleep = SpeechTiming.realSleep
    ) {
        self.input = input
        self.sleep = sleep
    }

    var isListening: Bool {
        self.phase == .listening
    }

    /// Listens for `locale`; `heard` gets the whole transcript so far each time it grows.
    func start(locale: Locale, heard: @escaping (String) -> Void) async {
        self.cancel()
        let attempt = self.attempt
        self.locale = locale
        self.heard = heard
        self.phase = .listening

        guard await self.input.authorize() else {
            if attempt == self.attempt { self.phase = .denied }
            return
        }
        guard attempt == self.attempt else { return }

        let events = SpeechListenEvents(
            result: { [weak self] text, isFinal, failed in
                self?.receive(text: text, isFinal: isFinal, failed: failed, attempt: attempt)
            },
            interrupted: { [weak self] in
                guard let self, attempt == self.attempt else { return }
                self.stop()
            }
        )
        switch self.input.open(SpeechListenRequest(locale: locale, punctuate: true), events: events) {
        case .listening: break
        case .unsupported:
            self.phase = .unavailable
            return
        case .offline:
            self.phase = .offline
            return
        case .failed:
            self.phase = .failed
            return
        }

        self.arm(after: Self.silence, attempt: attempt)
        let sleep = self.sleep
        self.ceiling = Task { [weak self] in
            await sleep(Self.maximum)
            guard !Task.isCancelled, let self, attempt == self.attempt else { return }
            self.stop()
        }
    }

    /// The person is done: close the mic and let the recogniser give its last word.
    func stop() {
        guard self.phase == .listening else { return }
        self.input.endAudio()
        self.timer?.cancel()
        self.ceiling?.cancel()
        self.phase = .idle
    }

    /// Drop it. Nothing more reaches the caller, and a problem shown is cleared.
    func cancel() {
        self.attempt += 1
        self.timer?.cancel()
        self.timer = nil
        self.ceiling?.cancel()
        self.ceiling = nil
        self.input.cancel()
        self.heard = { _ in }
        self.phase = .idle
    }

    // MARK: - Recogniser events

    private func receive(text: String?, isFinal: Bool, failed: Bool, attempt: Int) {
        guard attempt == self.attempt else { return }
        // The final result can come back empty after partials that were not;
        // what was already heard stands.
        if let text, !text.isEmpty {
            self.heard(text)
            if self.phase == .listening { self.arm(after: Self.pause, attempt: attempt) }
        }
        if isFinal || failed {
            // The recogniser reports silence as an error; nothing heard is not a problem to show.
            self.input.endAudio()
            self.timer?.cancel()
            self.ceiling?.cancel()
            if self.phase == .listening { self.phase = .idle }
        }
    }

    private func arm(after delay: Duration, attempt: Int) {
        self.timer?.cancel()
        let sleep = self.sleep
        self.timer = Task { [weak self] in
            await sleep(delay)
            guard !Task.isCancelled, let self, attempt == self.attempt else { return }
            self.stop()
        }
    }
}
