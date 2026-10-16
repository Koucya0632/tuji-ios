// 語音輸入 — speech into a draft. Hands back the running transcript while the
// person talks; what to do with it is the caller's. Nothing is recorded or kept.
//
// Apple's recogniser, on the device whenever the language allows it, as for
// 跟讀 (`ShadowingRecorder`). One language at a time: the recogniser listens for
// one locale, so switching language starts again.
//
// It stops by itself after a pause once something has been heard, after a
// longer wait if nothing ever was, and at a hard ceiling; `stop` ends it too.
// `cancel` drops it, and anything the recogniser says afterwards is ignored —
// for when the draft is about to be sent or typed into.

import AVFoundation
import Observation
import OSLog
import Speech

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
        case failed
    }

    private(set) var phase: Phase = .idle
    /// The language being listened for, while listening or after a problem.
    private(set) var locale: Locale?

    @ObservationIgnored private var engine: AVAudioEngine?
    @ObservationIgnored private var request: SFSpeechAudioBufferRecognitionRequest?
    @ObservationIgnored private var task: SFSpeechRecognitionTask?
    @ObservationIgnored private var timer: Task<Void, Never>?
    @ObservationIgnored private var ceiling: Task<Void, Never>?
    @ObservationIgnored private var heard: (String) -> Void = { _ in }
    /// Bumped on every start and cancel so a late callback from an earlier try is ignored.
    @ObservationIgnored private var attempt = 0

    @ObservationIgnored private let log = Logger(subsystem: "app.tuji.ios", category: "dictation")

    /// Stop after this long without a new word, once something was heard —
    /// longer than 跟讀's, because the person is thinking of what to say, not reading.
    private static let pause: Duration = .seconds(3)
    /// Give up after this long if nothing is heard at all.
    private static let silence: Duration = .seconds(8)
    /// Never listen longer than this.
    private static let maximum: Duration = .seconds(60)

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

        guard await SpeechRecognition.authorize() else {
            if attempt == self.attempt { self.phase = .denied }
            return
        }
        guard attempt == self.attempt else { return }
        guard let recognizer = SFSpeechRecognizer(locale: locale), recognizer.isAvailable else {
            self.phase = .unavailable
            return
        }

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.taskHint = .dictation
        request.addsPunctuation = true
        if recognizer.supportsOnDeviceRecognition {
            request.requiresOnDeviceRecognition = true
        }

        let engine = AVAudioEngine()
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .measurement, options: [.duckOthers, .defaultToSpeaker])
            try session.setActive(true, options: .notifyOthersOnDeactivation)
            let input = engine.inputNode
            input.installTap(
                onBus: 0,
                bufferSize: 1024,
                format: input.outputFormat(forBus: 0),
                block: Self.tap(request)
            )
            engine.prepare()
            try engine.start()
        } catch {
            self.log.error("dictation start failed: \(error.localizedDescription, privacy: .public)")
            engine.inputNode.removeTap(onBus: 0)
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
        self.ceiling = Task { [weak self] in
            try? await Task.sleep(for: Self.maximum)
            guard !Task.isCancelled, let self, attempt == self.attempt else { return }
            self.stop()
        }
    }

    /// The person is done: close the mic and let the recogniser give its last word.
    func stop() {
        guard self.phase == .listening else { return }
        self.closeMic()
        self.request?.endAudio()
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
        self.task?.cancel()
        self.task = nil
        self.request = nil
        self.closeMic()
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
            self.closeMic()
            self.timer?.cancel()
            self.ceiling?.cancel()
            self.task = nil
            self.request = nil
            if self.phase == .listening { self.phase = .idle }
        }
    }

    private func arm(after delay: Duration, attempt: Int) {
        self.timer?.cancel()
        self.timer = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled, let self, attempt == self.attempt else { return }
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

    private func releaseSession() {
        do {
            try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        } catch {
            self.log.error("dictation session release failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private nonisolated static func tap(_ request: SFSpeechAudioBufferRecognitionRequest) -> AVAudioNodeTapBlock {
        nonisolated(unsafe) let request = request
        return { buffer, _ in request.append(buffer) }
    }
}
