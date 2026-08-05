// Speaker button that fires SpeechService. Light haptic so taps feel
// responsive even before the synthesizer warms up.
//
// Square, not circular: a circle is the platform's accent, and this system
// reserves round shapes for the three things that "speak" as people (avatars,
// status dots, the cat's bubble). It was also pale teal, which now means
// accumulation — playing audio is not something you have accumulated. While a
// The spec also wants the ground to turn 瞳黃 while a clip plays. Not done:
// `SpeechService` is not `@Observable` and publishes no playing state, and
// inventing a local timer here would show a lie whenever playback fails or the
// audio is longer than the guess. It needs the service to say so.

import SwiftUI

struct PronunciationButton: View {
    let text: String
    /// The word's own language (`wordLanguage`); wins over the session
    /// direction when picking the voice. `nil` follows the learning
    /// direction + 發音口音 setting.
    var language: TargetLanguage?
    /// Pre-generated clips keyed by locale ("en-US"/"en-GB"/"ja-JP"). When the
    /// resolved voice has a clip it plays that; otherwise SpeechService falls
    /// back to on-device synthesis of `text`.
    var audioUrls: [String: String]?
    var size: CGFloat = 40
    /// Analytics only — set at call sites where the word id is public and
    /// worth attributing (word detail); nil elsewhere.
    var wordId: String?

    @Environment(SettingsStore.self) private var settings

    private var effectiveVoice: SpeechService.Voice {
        .preferred(for: self.settings.current, language: self.language)
    }

    var body: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            AnalyticsService.shared.track(.pronounce, wordId: self.wordId)
            SpeechService.shared.play(
                urlString: self.audioUrls?[self.effectiveVoice.rawValue],
                fallbackText: self.text,
                voice: self.effectiveVoice
            )
        } label: {
            ZStack {
                Rectangle().fill(.tujiPaper2)
                Image(systemName: "speaker.wave.2.fill")
                    .font(.system(size: self.size * 0.38, weight: .semibold))
                    .foregroundStyle(.tujiInk)
            }
            .frame(width: self.size, height: self.size)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("發音"))
    }
}

#Preview {
    PronunciationButton(text: "tomato")
        .environment(SettingsStore.shared)
}
