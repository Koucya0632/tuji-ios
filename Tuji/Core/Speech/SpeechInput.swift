// The device half of one listening session, shared by 語音輸入 (`Dictation`)
// and 跟讀 (`ShadowingRecorder`): the audio session, the mic tap, Apple's
// recogniser and, for 跟讀, the file the try is kept in. The two callers keep
// the timing and what the result means; this keeps the hardware, so there is
// one copy of it, and tests stand in for it with a fake.
//
// A call, Siri, or the route changing under the engine (headphones in or out)
// stops the mic without asking. `interrupted` says so, and the caller ends the
// try as if the person had stopped, keeping what was heard.
//
// The audio tap and the recogniser's callbacks run off the main actor; the
// closures they call are built in `nonisolated` functions, because under this
// target's default MainActor isolation a closure written in a method here would
// be MainActor-isolated, and the audio thread calling it traps.

import AVFoundation
import OSLog
import Speech

struct SpeechListenRequest {
    var locale: Locale
    /// Let the recogniser add punctuation: for text the person will send.
    var punctuate = false
    /// Where to keep the audio, for playing the try back.
    var recordTo: URL?
}

enum SpeechOpenOutcome: Equatable {
    case listening
    /// No recogniser for this language on this device.
    case unsupported
    /// The recogniser exists but can't be reached now.
    case offline
    /// The mic would not start.
    case failed
}

struct SpeechListenEvents {
    /// (text, isFinal, failed): the whole transcript so far.
    var result: @MainActor (String?, Bool, Bool) -> Void
    /// The system took the mic away.
    var interrupted: @MainActor () -> Void
}

protocol SpeechListening: AnyObject {
    /// Microphone, then speech recognition; both must be granted.
    func authorize() async -> Bool
    /// Opens the mic and starts recognising; drops any session still open.
    func open(_ request: SpeechListenRequest, events: SpeechListenEvents) -> SpeechOpenOutcome
    /// Closes the mic; the recogniser still gives its last word. Safe to repeat.
    func endAudio()
    /// Closes the mic and drops the recognition and any recording.
    func cancel()
    /// Closes the recording; its URL when it holds any sound.
    func finishRecording() -> URL?
}

final class LiveSpeechInput: SpeechListening {
    private var engine: AVAudioEngine?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var file: RecordingFile?
    private var observers: [NSObjectProtocol] = []
    private let log: Logger

    init(category: String) {
        self.log = Logger(subsystem: "app.tuji.ios", category: category)
    }

    func authorize() async -> Bool {
        await SpeechRecognition.authorize()
    }

    func open(_ wanted: SpeechListenRequest, events: SpeechListenEvents) -> SpeechOpenOutcome {
        self.cancel()
        guard let recognizer = SFSpeechRecognizer(locale: wanted.locale) else { return .unsupported }
        guard recognizer.isAvailable else { return .offline }

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.taskHint = .dictation
        request.addsPunctuation = wanted.punctuate
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
            let file = try wanted.recordTo.map { try RecordingFile(url: $0, format: format) }
            self.file = file
            input.installTap(onBus: 0, bufferSize: 1024, format: format, block: Self.tap(request, file: file))
            engine.prepare()
            try engine.start()
        } catch {
            self.log.error("listening start failed: \(error.localizedDescription, privacy: .public)")
            engine.inputNode.removeTap(onBus: 0)
            self.file?.close()
            self.file = nil
            self.releaseSession()
            return .failed
        }

        self.engine = engine
        self.request = request
        self.observers = Self.watch(engine, interrupted: events.interrupted)
        self.task = recognizer.recognitionTask(with: request, resultHandler: SpeechRecognition.handler(events.result))
        return .listening
    }

    func endAudio() {
        self.closeMic()
        self.request?.endAudio()
    }

    func cancel() {
        self.task?.cancel()
        self.task = nil
        self.closeMic()
        self.request = nil
        self.file?.close()
        self.file = nil
    }

    func finishRecording() -> URL? {
        guard let file = self.file else { return nil }
        self.file = nil
        file.close()
        return file.hasAudio ? file.url : nil
    }

    private func closeMic() {
        for observer in self.observers {
            NotificationCenter.default.removeObserver(observer)
        }
        self.observers = []
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
            self.log.error("listening session release failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Off the main actor

    private nonisolated static func tap(
        _ request: SFSpeechAudioBufferRecognitionRequest,
        file: RecordingFile?
    )
        -> AVAudioNodeTapBlock
    {
        nonisolated(unsafe) let request = request
        return { buffer, _ in
            request.append(buffer)
            file?.write(buffer)
        }
    }

    /// An interruption beginning, the engine's route changing, or the media
    /// server restarting: each one stops the engine under us.
    private nonisolated static func watch(
        _ engine: AVAudioEngine,
        interrupted: @escaping @MainActor () -> Void
    )
        -> [NSObjectProtocol]
    {
        let center = NotificationCenter.default
        let session = AVAudioSession.sharedInstance()
        let tell: @Sendable (Notification) -> Void = { _ in Task { @MainActor in interrupted() } }
        return [
            center.addObserver(forName: AVAudioSession.interruptionNotification, object: session, queue: nil) { note in
                let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
                guard raw.flatMap(AVAudioSession.InterruptionType.init(rawValue:)) == .began else { return }
                tell(note)
            },
            center.addObserver(forName: .AVAudioEngineConfigurationChange, object: engine, queue: nil, using: tell),
            center.addObserver(
                forName: AVAudioSession.mediaServicesWereResetNotification,
                object: session,
                queue: nil,
                using: tell
            )
        ]
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

/// How a session waits out its timers. Tests pass a clock they move by hand.
typealias SpeechSleep = @MainActor (Duration) async -> Void

enum SpeechTiming {
    static let realSleep: SpeechSleep = { try? await Task.sleep(for: $0) }
}
