// 跟讀 — listens to the person read a line back, scores it, and keeps the
// recording so they can hear themselves. The recording is one temporary file,
// replaced by the next try and never uploaded.
//
// Apple's speech recogniser, on the device whenever the language allows it, so
// a try costs nothing and the audio does not leave the phone. When a language
// has no on-device model the recogniser falls back to Apple's server, which is
// still free to us; the permission text says speech is recognised by Apple.
//
// One line at a time. `start` for another line stops the one in progress. It
// stops by itself after a pause once something has been heard, after a longer
// wait if nothing ever was, and at a hard ceiling; tapping again stops it too.
//
// The mic, the recogniser and the recording file are `SpeechListening`'s,
// shared with 語音輸入; this keeps the timing and the score. When the system
// takes the mic away (a call, the route changing), the try is scored on what
// was heard so far.
//
// The audio session is switched to play-and-record while listening and handed
// back afterwards; `SpeechService` sets its own category again on the next play.

import AVFoundation
import Observation
import OSLog

@MainActor
@Observable
final class ShadowingRecorder {
    enum Phase: Equatable {
        case idle
        /// Mic open. `heard` is the running transcript.
        case listening(heard: String)
        /// Mic closed, waiting for the recogniser's last word.
        case finishing
        case scored(ShadowingScore, heard: String)
        /// Microphone or speech recognition was refused.
        case denied
        /// No recogniser for this language on this device.
        case unavailable
        /// The recogniser exists but can't be reached now: a language that
        /// only runs on Apple's servers, with no network.
        case offline
        case failed
    }

    /// Which line `phase` is about, so a line only shows its own result.
    private(set) var lineID: Int?
    private(set) var phase: Phase = .idle
    /// The scored try's audio, while there is one to play back.
    private(set) var recording: URL?
    private(set) var isPlayingBack = false

    @ObservationIgnored private let input: SpeechListening
    @ObservationIgnored private let sleep: SpeechSleep
    @ObservationIgnored private var target = ""
    @ObservationIgnored private var language: TargetLanguage = .en
    @ObservationIgnored private var timer: Task<Void, Never>?
    @ObservationIgnored private var ceiling: Task<Void, Never>?
    @ObservationIgnored private var player: AVAudioPlayer?
    @ObservationIgnored private var playbackEnded: PlaybackEnded?
    /// Bumped on every start so a late callback from an earlier try is ignored.
    @ObservationIgnored private var attempt = 0

    @ObservationIgnored private let log = Logger(subsystem: "app.tuji.ios", category: "shadowing")

    /// Stop after this long without a new word, once something was heard.
    /// Long enough for the breath between two sentences of a line, and for the
    /// recogniser, which reports a word a beat after it is said.
    static let pause: Duration = .milliseconds(2500)
    /// Give up after this long if nothing is heard at all.
    static let silence: Duration = .seconds(6)
    /// Never listen longer than this.
    static let maximum: Duration = .seconds(20)
    /// How long a stopped try waits for the recogniser's last word.
    static let lastWord: Duration = .seconds(2)

    init(
        input: SpeechListening = LiveSpeechInput(category: "shadowing"),
        sleep: @escaping SpeechSleep = SpeechTiming.realSleep
    ) {
        self.input = input
        self.sleep = sleep
    }

    var isListening: Bool {
        if case .listening = self.phase { return true }
        return false
    }

    func isActive(line: Int) -> Bool {
        guard self.lineID == line else { return false }
        switch self.phase {
        case .listening, .finishing: return true
        default: return false
        }
    }

    func start(line: Int, target: String, language: TargetLanguage) async {
        self.cancel()
        self.attempt += 1
        let attempt = self.attempt
        self.lineID = line
        self.target = target
        self.language = language
        // Not .listening yet: while the system asks for the mic, nothing is.

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
        let request = SpeechListenRequest(locale: Self.locale(for: language), recordTo: Self.recordingURL)
        switch self.input.open(request, events: events) {
        case .listening:
            self.phase = .listening(heard: "")
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

    /// The person is done: close the mic and score what was heard.
    func stop() {
        guard case .listening = self.phase else { return }
        self.input.endAudio()
        self.ceiling?.cancel()
        self.phase = .finishing
        let attempt = self.attempt
        // The final result normally follows within a moment. If it does not,
        // score the last partial rather than leave the line spinning.
        self.timer?.cancel()
        let sleep = self.sleep
        self.timer = Task { [weak self] in
            await sleep(Self.lastWord)
            guard !Task.isCancelled, let self, attempt == self.attempt, self.phase == .finishing else { return }
            self.finish(heard: self.lastHeard)
        }
    }

    /// Drop everything, result included. Leaving the page, or starting again.
    func cancel() {
        self.attempt += 1
        self.stopPlayback()
        self.recording = nil
        self.timer?.cancel()
        self.timer = nil
        self.ceiling?.cancel()
        self.ceiling = nil
        self.input.cancel()
        self.lastHeard = ""
        self.lineID = nil
        self.phase = .idle
    }

    // MARK: - Recogniser events

    @ObservationIgnored private var lastHeard = ""

    private func receive(text: String?, isFinal: Bool, failed: Bool, attempt: Int) {
        guard attempt == self.attempt else { return }
        // The final result can come back empty after partials that were not —
        // seen on the on-device recogniser once the mic closes. What was
        // already heard stands.
        if let text, !text.isEmpty {
            self.lastHeard = text
            if case .listening = self.phase {
                self.phase = .listening(heard: text)
                self.arm(after: Self.pause, attempt: attempt)
            }
        }
        if isFinal || failed {
            // A failure with nothing heard is "nothing heard", which scores as
            // try again — the recogniser reports silence as an error.
            self.input.endAudio()
            self.finish(heard: self.lastHeard)
        }
    }

    private func finish(heard: String) {
        self.timer?.cancel()
        self.timer = nil
        self.ceiling?.cancel()
        self.ceiling = nil
        let score = ShadowingScore(target: self.target, heard: heard, language: self.language)
        self.phase = .scored(score, heard: heard)
        self.recording = self.input.finishRecording()
        self.lastHeard = ""
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

    // MARK: - 聽自己

    /// Plays the scored try, or stops it when it is already playing.
    func playRecording() {
        if self.isPlayingBack {
            self.stopPlayback()
            return
        }
        guard let recording else { return }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default)
            try session.setActive(true)
            let player = try AVAudioPlayer(contentsOf: recording)
            let ended = PlaybackEnded { [weak self] in self?.stopPlayback() }
            player.delegate = ended
            guard player.play() else { return }
            self.player = player
            self.playbackEnded = ended
            self.isPlayingBack = true
        } catch {
            self.log.error("shadowing playback failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    func stopPlayback() {
        self.player?.stop()
        self.player = nil
        self.playbackEnded = nil
        self.isPlayingBack = false
    }

    // MARK: - Off the main actor

    private nonisolated static func locale(for language: TargetLanguage) -> Locale {
        switch language {
        case .ja: Locale(identifier: "ja-JP")
        case .en: Locale(identifier: "en-US")
        }
    }

    private nonisolated static var recordingURL: URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("shadowing.caf")
    }
}

/// Tells the recorder its playback reached the end.
private final class PlaybackEnded: NSObject, AVAudioPlayerDelegate {
    private let ended: @MainActor () -> Void

    init(_ ended: @escaping @MainActor () -> Void) {
        self.ended = ended
    }

    nonisolated func audioPlayerDidFinishPlaying(_: AVAudioPlayer, successfully _: Bool) {
        Task { @MainActor in self.ended() }
    }
}
