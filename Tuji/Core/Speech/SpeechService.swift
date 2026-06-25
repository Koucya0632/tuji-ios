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

import AVFoundation
import OSLog

@MainActor
final class SpeechService: NSObject, AVSpeechSynthesizerDelegate, AVAudioPlayerDelegate {
    enum Voice: String, CaseIterable {
        case us = "en-US"
        case uk = "en-GB"
        case japanese = "ja-JP"
    }

    static let shared = SpeechService()

    private let log = Logger(subsystem: "app.tuji.ios", category: "speech")

    /// Lazy so `self` is available to wire up the finish delegate without a
    /// custom initializer.
    private lazy var synth: AVSpeechSynthesizer = {
        let synth = AVSpeechSynthesizer()
        synth.delegate = self
        return synth
    }()

    /// Holds the currently-playing pre-generated clip. Retained so playback
    /// isn't cut short by deallocation.
    private var player: AVAudioPlayer?
    /// In-flight clip download; cancelled when a newer tap supersedes it.
    private var downloadTask: Task<Void, Never>?

    /// On-disk cache for downloaded clips so the second tap is instant and
    /// repeat plays work offline. Lives under Caches (purgeable by the OS).
    private lazy var cacheDir: URL = {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("word-audio", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    // MARK: - Pre-generated clip playback

    /// Play a pre-generated Chirp clip, falling back to on-device synthesis
    /// when the URL is missing/invalid or the download/decode fails. `voice`
    /// is only used for the fallback so its accent matches the request.
    func play(urlString: String?, fallbackText: String, voice: Voice = .us) {
        guard let urlString, let url = URL(string: urlString) else {
            self.speak(fallbackText, voice: voice)
            return
        }

        // Cancel any prior speech/clip so rapid taps don't overlap.
        self.synth.stopSpeaking(at: .immediate)
        self.player?.stop()
        self.downloadTask?.cancel()

        let local = self.cacheURL(for: url)
        if FileManager.default.fileExists(atPath: local.path) {
            self.playFile(local, fallbackText: fallbackText, voice: voice)
            return
        }

        self.downloadTask = Task { [weak self] in
            do {
                let (data, response) = try await URLSession.shared.data(from: url)
                if let http = response as? HTTPURLResponse, !(200 ..< 300).contains(http.statusCode) {
                    throw URLError(.badServerResponse)
                }
                try Task.checkCancellation()
                try data.write(to: local, options: .atomic)
                await MainActor.run {
                    self?.playFile(local, fallbackText: fallbackText, voice: voice)
                }
            } catch is CancellationError {
                // Superseded by a newer tap — nothing to do.
            } catch {
                await MainActor.run {
                    self?.log.error("clip download failed: \(error.localizedDescription, privacy: .public)")
                    self?.speak(fallbackText, voice: voice)
                }
            }
        }
    }

    private func playFile(_ file: URL, fallbackText: String, voice: Voice) {
        self.activateSession()
        do {
            let player = try AVAudioPlayer(contentsOf: file)
            player.delegate = self
            self.player = player
            player.play()
            self.log.info("play clip \(file.lastPathComponent, privacy: .public)")
        } catch {
            self.log.error("clip play failed: \(error.localizedDescription, privacy: .public)")
            self.speak(fallbackText, voice: voice)
        }
    }

    /// Stable, collision-free cache name: the last two path components keep
    /// the per-word folder (e.g. "<id>_en-US.mp3"), so different words don't
    /// clash on the shared "en-US.mp3" leaf.
    private func cacheURL(for remote: URL) -> URL {
        let name = remote.pathComponents.suffix(2).joined(separator: "_")
        return self.cacheDir.appendingPathComponent(name.isEmpty ? remote.lastPathComponent : name)
    }

    func speak(_ text: String, voice: Voice = .us) {
        self.player?.stop()
        self.synth.stopSpeaking(at: .immediate)
        self.activateSession()
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: voice.rawValue)
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 0.92
        utterance.pitchMultiplier = 1.0
        self.synth.speak(utterance)
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
        Task { @MainActor in self.deactivateSession() }
    }

    /// Mirror of the synthesizer finish handler for pre-generated clips.
    nonisolated func audioPlayerDidFinishPlaying(_: AVAudioPlayer, successfully _: Bool) {
        Task { @MainActor in self.deactivateSession() }
    }
}
