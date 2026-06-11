// AVSpeechSynthesizer wrapper for word pronunciation. Picks the iOS
// system voice that matches the user's accent setting (US default, UK
// optional — set via Settings later).
//
// `stop()` is idempotent and runs before every new utterance so rapid
// taps don't queue up overlapping speech.

import AVFoundation
import OSLog

@MainActor
final class SpeechService {
    enum Accent: String, CaseIterable {
        case us = "en-US"
        case uk = "en-GB"
    }

    static let shared = SpeechService()

    private let synth = AVSpeechSynthesizer()
    private let log = Logger(subsystem: "app.tuji.ios", category: "speech")

    private init() {}

    func speak(_ text: String, accent: Accent = .us) {
        self.synth.stopSpeaking(at: .immediate)
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: accent.rawValue)
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 0.92
        utterance.pitchMultiplier = 1.0
        self.synth.speak(utterance)
        self.log.info("speak \(text, privacy: .public) accent=\(accent.rawValue, privacy: .public)")
    }

    func stop() {
        self.synth.stopSpeaking(at: .immediate)
    }
}
