// Circular speaker button that fires SpeechService. Light haptic so
// taps feel responsive even before the synthesizer warms up.

import SwiftUI

struct PronunciationButton: View {
    let text: String
    /// Explicit override; `nil` means follow the user's 發音口音 setting.
    var voice: SpeechService.Voice?
    var size: CGFloat = 40

    @Environment(SettingsStore.self) private var settings

    /// Resolve the accent: explicit param wins, otherwise map the saved
    /// setting code ("us"/"uk") to a SpeechService voice.
    private var effectiveVoice: SpeechService.Voice {
        if let voice { return voice }
        if self.settings.current.learningDirection == .zhJa {
            return .japanese
        }
        return self.settings.current.accent == "uk" ? .uk : .us
    }

    var body: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            SpeechService.shared.speak(self.text, voice: self.effectiveVoice)
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
