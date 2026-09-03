// AVSpeechSynthesizer wrapper for word pronunciation. Picks the iOS
// system voice that matches the user's accent setting (US default, UK
// optional — set via Settings later).
//
// `stop()` is idempotent and runs before every new utterance so rapid
// taps don't queue up overlapping speech.
//
// Pronunciation routes through the `.playback` audio session category so
// it stays audible even when the hardware silent switch is on (the
// default category obeys the mute switch and produces no sound).

// It publishes what it is doing (`playback`), which 聽句 needs: its clock may
// only start once the sentence has finished playing, or the 3s/7s thresholds
// end up measuring a download and a sentence rather than recall (ADR-0014).
// That also closes the gap `PronunciationButton` has been documenting since it
// shipped — the ground was meant to turn 瞳黃 while a clip plays, and could not,
// because this service said nothing.
//
// The state is **per request**, not a single "am I playing" flag. This is a
// singleton and 複習's hero already has a `PronunciationButton` on it that
// speaks the answer word; a global flag would let that button's clip finish and
// start the listening clock. Callers keep the id `play`/`speak` hands back and
// ignore any state that is not theirs.
//
// `@ObservationIgnored` on the stored properties is not decoration: `@Observable`
// rewrites stored properties into computed ones and `lazy` cannot be applied to
// a computed property, so `synth` and `cacheDir` do not compile without it.

import AVFoundation
import Observation
import OSLog

@MainActor
@Observable
final class SpeechService: NSObject, AVSpeechSynthesizerDelegate, AVAudioPlayerDelegate {
    /// Where one playback request has got to.
    ///
    /// `finished` means the audio reached its end on its own. A request that is
    /// superseded by a newer tap never reaches it and never will — the caller
    /// finds out because the newer request has a different id.
    struct PlaybackState: Equatable {
        enum Phase: Equatable {
            /// Downloading the clip. Only pre-generated clips pass through here.
            case loading
            case playing
            /// Reached the end on its own.
            case finished
            /// Nothing came out at all.
            case failed
        }

        let requestID: Int
        let phase: Phase
        /// The pre-generated clip was missing or unreachable, so this is
        /// on-device synthesis. 聽句 records it as `audioFailed`: the sentence
        /// was still read aloud, but by a reading nothing can correct, so the
        /// answer is not evidence about listening either way.
        let usedFallback: Bool
    }

    /// The most recent request's state. Nil before anything has been asked for.
    private(set) var playback: PlaybackState?

    @ObservationIgnored private var lastRequestID = 0

    enum Voice: String, CaseIterable {
        case us = "en-US"
        case uk = "en-GB"
        case japanese = "ja-JP"

        /// Voice for a word: its own `taggedLanguage` when the payload carries
        /// one (so a JA word speaks Japanese even outside a JA session), else
        /// 當前圖鑑語言; English resolves through the saved 發音口音 setting
        /// ("us"/"uk"). Shared by PronunciationButton and the study flows'
        /// auto-play so the resolutions can't drift.
        static func preferred(for settings: UserSettings, language: TargetLanguage? = nil) -> Voice {
            switch language ?? settings.learningDirection.targetLanguage {
            case .ja: .japanese
            case .en: settings.accent == "uk" ? .uk : .us
            }
        }
    }

    static let shared = SpeechService()

    @ObservationIgnored private let log = Logger(subsystem: "app.tuji.ios", category: "speech")

    /// Lazy so `self` is available to wire up the finish delegate without a
    /// custom initializer. `@ObservationIgnored` is load-bearing — see the file
    /// header: `@Observable` turns stored properties computed, and `lazy` on a
    /// computed property does not compile.
    @ObservationIgnored private lazy var synth: AVSpeechSynthesizer = {
        let synth = AVSpeechSynthesizer()
        synth.delegate = self
        return synth
    }()

    /// Holds the currently-playing pre-generated clip. Retained so playback
    /// isn't cut short by deallocation.
    @ObservationIgnored private var player: AVAudioPlayer?
    /// In-flight clip download; cancelled when a newer tap supersedes it.
    @ObservationIgnored private var downloadTask: Task<Void, Never>?

    /// On-disk cache for downloaded clips so the second tap is instant and
    /// repeat plays work offline. Lives under Caches (purgeable by the OS).
    @ObservationIgnored private lazy var cacheDir: URL = {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("word-audio", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    // MARK: - Pre-generated clip playback

    /// Whether this clip is already on disk, i.e. whether it will play with no
    /// network at all.
    ///
    /// 聽句 asks before it commits to the question: offline with nothing cached,
    /// `play` falls through to on-device synthesis, and a sentence read by a
    /// kanji reading the app cannot correct is not a harder question but an
    /// unanswerable one. That card takes 選字 instead (ADR-0014).
    func hasCachedClip(for urlString: String?) -> Bool {
        guard let urlString, let url = URL(string: urlString) else { return false }
        return FileManager.default.fileExists(atPath: self.cacheURL(for: url).path)
    }

    /// Play a pre-generated Chirp clip, falling back to on-device synthesis
    /// when the URL is missing/invalid or the download/decode fails. `voice`
    /// is only used for the fallback so its accent matches the request.
    ///
    /// Returns the request id. Callers that care when this finishes (聽句's
    /// clock) keep it and ignore any `playback` whose `requestID` differs —
    /// otherwise the hero's own pronunciation button, which shares this
    /// singleton, would resolve their wait.
    @discardableResult
    func play(urlString: String?, fallbackText: String, voice: Voice = .us) -> Int {
        let request = self.beginRequest()
        guard let urlString, let url = URL(string: urlString) else {
            self.synthesize(fallbackText, voice: voice, request: request, isFallback: true)
            return request
        }

        // Cancel any prior speech/clip so rapid taps don't overlap.
        self.synth.stopSpeaking(at: .immediate)
        self.player?.stop()
        self.downloadTask?.cancel()

        let local = self.cacheURL(for: url)
        if FileManager.default.fileExists(atPath: local.path) {
            self.playFile(local, fallbackText: fallbackText, voice: voice, request: request)
            return request
        }

        self.publish(request, .loading, usedFallback: false)
        self.downloadTask = Task { [weak self] in
            do {
                // Raw audio-clip download from an absolute (storage) URL — not an
                // API call, so APIClient's Endpoint/JSON pipeline doesn't apply.
                // swiftlint:disable:next no_urlsession_outside_networking
                let (data, response) = try await URLSession.shared.data(from: url)
                if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                    throw URLError(.badServerResponse)
                }
                try Task.checkCancellation()
                try data.write(to: local, options: .atomic)
                await MainActor.run {
                    self?.playFile(local, fallbackText: fallbackText, voice: voice, request: request)
                }
            } catch is CancellationError {
                // Superseded by a newer tap — nothing to do.
            } catch {
                await MainActor.run {
                    self?.log.error("clip download failed: \(error.localizedDescription, privacy: .public)")
                    self?.synthesize(fallbackText, voice: voice, request: request, isFallback: true)
                }
            }
        }
        return request
    }

    private func playFile(_ file: URL, fallbackText: String, voice: Voice, request: Int) {
        self.activateSession()
        do {
            let player = try AVAudioPlayer(contentsOf: file)
            player.delegate = self
            self.player = player
            player.play()
            self.publish(request, .playing, usedFallback: false)
            self.log.info("play clip \(file.lastPathComponent, privacy: .public)")
        } catch {
            self.log.error("clip play failed: \(error.localizedDescription, privacy: .public)")
            self.synthesize(fallbackText, voice: voice, request: request, isFallback: true)
        }
    }

    // MARK: - Request bookkeeping

    private func beginRequest() -> Int {
        self.lastRequestID += 1
        return self.lastRequestID
    }

    /// Only the newest request may write state. A superseded download that
    /// lands late would otherwise overwrite the state of the tap that replaced
    /// it — and the waiter is keyed on the id, so it would wait forever.
    private func publish(_ request: Int, _ phase: PlaybackState.Phase, usedFallback: Bool) {
        guard request == self.lastRequestID else { return }
        self.playback = PlaybackState(
            requestID: request,
            phase: phase,
            usedFallback: usedFallback
        )
    }

    /// Resolve whichever request is outstanding. The delegates fire without
    /// knowing which request they belong to; the newest is the only one that
    /// can still be playing, because starting a new one stops the old.
    private func finishCurrent(_ phase: PlaybackState.Phase) {
        guard let current = self.playback, current.phase == .playing else { return }
        self.playback = PlaybackState(
            requestID: current.requestID,
            phase: phase,
            usedFallback: current.usedFallback
        )
    }

    /// Stable, collision-free cache name: the last two path components keep
    /// the per-word folder (e.g. "<id>_en-US.mp3"), so different words don't
    /// clash on the shared "en-US.mp3" leaf.
    private func cacheURL(for remote: URL) -> URL {
        let name = remote.pathComponents.suffix(2).joined(separator: "_")
        return self.cacheDir.appendingPathComponent(name.isEmpty ? remote.lastPathComponent : name)
    }

    @discardableResult
    func speak(_ text: String, voice: Voice = .us) -> Int {
        let request = self.beginRequest()
        self.synthesize(text, voice: voice, request: request, isFallback: false)
        return request
    }

    /// The synthesis half, reusable by `play`'s fallback so a clip that could
    /// not be fetched keeps the *caller's* request id instead of minting a new
    /// one the caller is not waiting on.
    private func synthesize(_ text: String, voice: Voice, request: Int, isFallback: Bool) {
        self.player?.stop()
        self.synth.stopSpeaking(at: .immediate)
        self.activateSession()
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: voice.rawValue)
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 0.92
        utterance.pitchMultiplier = 1.0
        self.synth.speak(utterance)
        self.publish(request, .playing, usedFallback: isFallback)
        self.log.info("speak \(text, privacy: .public) voice=\(voice.rawValue, privacy: .public)")
    }

    func stop() {
        self.downloadTask?.cancel()
        self.player?.stop()
        self.synth.stopSpeaking(at: .immediate)
    }

    // MARK: - Audio session

    /// `.playback` makes speech audible regardless of the silent switch.
    /// `.duckOthers` momentarily lowers any background audio instead of
    /// stopping it; the session is deactivated once speech finishes (see
    /// the delegate below) so ducked audio returns to full volume.
    private func activateSession() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
            try session.setActive(true)
        } catch {
            self.log.error("audio session activate failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func deactivateSession() {
        do {
            try AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
        } catch {
            self.log.error("audio session deactivate failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Only deactivate on a natural finish. Cancellation (from `stopSpeaking`
    /// at the top of `speak`) is followed immediately by a new utterance, so
    /// leaving the session active there avoids a deactivate/reactivate churn.
    nonisolated func speechSynthesizer(_: AVSpeechSynthesizer, didFinish _: AVSpeechUtterance) {
        Task { @MainActor in
            self.finishCurrent(.finished)
            self.deactivateSession()
        }
    }

    /// Mirror of the synthesizer finish handler for pre-generated clips.
    ///
    /// `successfully == false` still ends the request — the audio is over
    /// either way, and 聽句 must not sit waiting for a finish that will never
    /// arrive. It resolves as `.failed` so the answer is not read as evidence
    /// about listening.
    nonisolated func audioPlayerDidFinishPlaying(_: AVAudioPlayer, successfully ok: Bool) {
        Task { @MainActor in
            self.finishCurrent(ok ? .finished : .failed)
            self.deactivateSession()
        }
    }
}
