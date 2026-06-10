// Circular speaker button that fires SpeechService. Light haptic so
// taps feel responsive even before the synthesizer warms up.

import SwiftUI

struct PronunciationButton: View {
    let text: String
    var accent: SpeechService.Accent = .us
    var size: CGFloat = 40

    var body: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            SpeechService.shared.speak(self.text, accent: self.accent)
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
}
