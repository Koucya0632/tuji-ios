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
// The audio tap and the recogniser's callbacks run off the main actor. Both are
// built in `nonisolated` functions (the callback in `SpeechRecognition`) and
// hand plain strings back, because under this target's default MainActor
// isolation a closure written inside a method here would be MainActor-isolated,
// and the audio thread calling it traps.
//
// The audio session is switched to play-and-record while listening and handed
// back afterwards; `SpeechService` sets its own category again on the next play.

import AVFoundation
import Observation
import OSLog
import Speech

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
        case failed
    }

    /// Which line `phase` is about, so a line only shows its own result.
    private(set) var lineID: Int?
    private(set) var phase: Phase = .idle
    /// The scored try's audio, while there is one to play back.
    private(set) var recording: URL?
    private(set) var isPlayingBack = false

    @ObservationIgnored private var target = ""
    @ObservationIgnored private var language: TargetLanguage = .en
    @ObservationIgnored private var engine: AVAudioEngine?
    @ObservationIgnored private var request: SFSpeechAudioBufferRecognitionRequest?
    @ObservationIgnored private var task: SFSpeechRecognitionTask?
    @ObservationIgnored private var timer: Task<Void, Never>?
    @ObservationIgnored private var file: RecordingFile?
    @ObservationIgnored private var player: AVAudioPlayer?
    @ObservationIgnored private var playbackEnded: PlaybackEnded?
    /// Bumped on every start so a late callback from an earlier try is ignored.
    @ObservationIgnored private var attempt = 0

    @ObservationIgnored private let log = Logger(subsystem: "app.tuji.ios", category: "shadowing")

    /// Stop after this long without a new word, once something was heard.
    /// Long enough for the breath between two sentences of a line, and for the
    /// recogniser, which reports a word a beat after it is said.
    private static let pause: Duration = .milliseconds(2500)
    /// Give up after this long if nothing is heard at all.
    private static let silence: Duration = .seconds(6)
    /// Never listen longer than this.
    private static let ceiling: Duration = .seconds(20)

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
        self.phase = .listening(heard: "")

        guard await SpeechRecognition.authorize() else {
            if attempt == self.attempt { self.phase = .denied }
            return
        }
        guard attempt == self.attempt else { return }
        guard let recognizer = SFSpeechRecognizer(locale: Self.locale(for: language)), recognizer.isAvailable else {
            self.phase = .unavailable
            return
        }

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.taskHint = .dictation
        if recognizer.supportsOnDeviceRecognition {
            request.requiresOnDeviceRecognition = true
        }

        let engine = AVAudioEngine()
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .measurement, options: [.duckOthers, .defaultToSpeaker])
            try session.setActive(true, options: .notifyOthersOnDeactivation)
            let input = engine.inputNode
            let format = input.outputFormat(forBus: 0)
            let file = try RecordingFile(url: Self.recordingURL, format: format)
            self.file = file
            input.installTap(
                onBus: 0,
                bufferSize: 1024,
                format: format,
                block: Self.tap(request, file: file)
            )
            engine.prepare()
            try engine.start()
        } catch {
            self.log.error("shadowing start failed: \(error.localizedDescription, privacy: .public)")
            engine.inputNode.removeTap(onBus: 0)
            self.file?.close()
            self.file = nil
            self.releaseSession()
            self.phase = .failed
            return
        }

        self.engine = engine
        self.request = request
        self.task = recognizer.recognitionTask(
            with: request,
            resultHandler: SpeechRecognition.handler { [weak self] text, isFinal, failed in
                self?.receive(text: text, isFinal: isFinal, failed: failed, attempt: attempt)
            }
        )
        self.arm(after: Self.silence, attempt: attempt)
        self.ceilingTimer(attempt: attempt)
    }

    /// The person is done: close the mic and score what was heard.
    func stop() {
        guard case .listening = self.phase else { return }
        self.closeMic()
        self.phase = .finishing
        self.request?.endAudio()
        let attempt = self.attempt
        // The final result normally follows within a moment. If it does not,
        // score the last partial rather than leave the line spinning.
        self.timer?.cancel()
        self.timer = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
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
        self.task?.cancel()
        self.task = nil
        self.closeMic()
        self.file?.close()
        self.file = nil
        self.request = nil
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
            self.closeMic()
            self.finish(heard: self.lastHeard)
        }
    }

    private func finish(heard: String) {
        self.timer?.cancel()
        self.timer = nil
        self.task = nil
        self.request = nil
        let score = ShadowingScore(target: self.target, heard: heard, language: self.language)
        self.phase = .scored(score, heard: heard)
        self.closeFile()
        self.lastHeard = ""
    }

    private func arm(after delay: Duration, attempt: Int) {
        self.timer?.cancel()
        self.timer = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled, let self, attempt == self.attempt else { return }
            self.stop()
        }
    }

    private func ceilingTimer(attempt: Int) {
        Task { [weak self] in
            try? await Task.sleep(for: Self.ceiling)
            guard let self, attempt == self.attempt else { return }
            self.stop()
        }
    }

    private func closeMic() {
        guard let engine = self.engine else { return }
        engine.stop()
        engine.inputNode.removeTap(onBus: 0)
        self.engine = nil
        self.releaseSession()
    }

    /// The try is over: the file is complete, and playable when it holds any sound.
    private func closeFile() {
        guard let file = self.file else { return }
        self.file = nil
        file.close()
        self.recording = file.hasAudio ? file.url : nil
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

    private func releaseSession() {
        do {
            try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        } catch {
            self.log.error("shadowing session release failed: \(error.localizedDescription, privacy: .public)")
        }
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

    private nonisolated static func tap(
        _ request: SFSpeechAudioBufferRecognitionRequest,
        file: RecordingFile
    )
        -> AVAudioNodeTapBlock
    {
        nonisolated(unsafe) let request = request
        return { buffer, _ in
            request.append(buffer)
            file.write(buffer)
        }
    }
}

/// The mic's audio on its way to disk. Written from the audio thread, closed
/// from the main actor after the tap is gone; the lock covers the overlap.
private final nonisolated class RecordingFile: @unchecked Sendable {
    let url: URL
    private var file: AVAudioFile?
    private var frames: AVAudioFramePosition = 0
    private let lock = NSLock()

    init(url: URL, format: AVAudioFormat) throws {
        try? FileManager.default.removeItem(at: url)
        self.url = url
        self.file = try AVAudioFile(
            forWriting: url,
            settings: format.settings,
            commonFormat: format.commonFormat,
            interleaved: format.isInterleaved
        )
    }

    var hasAudio: Bool {
        self.lock.withLock { self.frames > 0 }
    }

    func write(_ buffer: AVAudioPCMBuffer) {
        self.lock.withLock {
            guard let file = self.file, (try? file.write(from: buffer)) != nil else { return }
            self.frames += AVAudioFramePosition(buffer.frameLength)
        }
    }

    func close() {
        self.lock.withLock {
            self.file?.close()
            self.file = nil
        }
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
