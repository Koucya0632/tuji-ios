// Circular speaker button that fires SpeechService. Light haptic so
// taps feel responsive even before the synthesizer warms up.

import SwiftUI

struct PronunciationButton: View {
    let text: String
    /// Explicit override; `nil` means follow the user's 發音口音 setting.
    var voice: SpeechService.Voice?
    /// Pre-generated clips keyed by locale ("en-US"/"en-GB"/"ja-JP"). When the
    /// resolved voice has a clip it plays that; otherwise SpeechService falls
    /// back to on-device synthesis of `text`.
    var audioUrls: [String: String]?
    var size: CGFloat = 40

    @Environment(SettingsStore.self) private var settings

    /// Resolve the accent: explicit param wins, otherwise the shared
    /// settings-based default.
    private var effectiveVoice: SpeechService.Voice {
        self.voice ?? .preferred(for: self.settings.current)
    }

    var body: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            SpeechService.shared.play(
                urlString: self.audioUrls?[self.effectiveVoice.rawValue],
                fallbackText: self.text,
                voice: self.effectiveVoice
            )
        } label: {
            ZStack {
                Circle().fill(.tujiTealSoft)
                Image(systemName: "speaker.wave.2.fill")
                    .font(.system(size: self.size * 0.4, weight: .heavy))
                    .foregroundStyle(.tujiTeal)
            }
            .frame(width: self.size, height: self.size)
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    PronunciationButton(text: "tomato")
        .environment(SettingsStore.shared)
}
