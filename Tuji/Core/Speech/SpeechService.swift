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
final class SpeechService: NSObject, AVSpeechSynthesizerDelegate {
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

    func speak(_ text: String, voice: Voice = .us) {
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
}
