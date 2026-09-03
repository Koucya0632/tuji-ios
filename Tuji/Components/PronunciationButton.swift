// Speaker button that fires SpeechService. Light haptic so taps feel
// responsive even before the synthesizer warms up.
//
// Square, not circular: a circle is the platform's accent, and this system
// reserves round shapes for the three things that "speak" as people (avatars,
// status dots, the cat's bubble). It was also pale teal, which now means
// accumulation — playing audio is not something you have accumulated.
//
// The ground turns 瞳黃 while this button's own clip plays. It carries the
// request id `play` hands back and ignores any state that is not its own: the
// service is a singleton, and 複習's hero has one of these on it beside the
// listening question's sentence — a global "am I playing" flag would let one
// button's clip light the other.
//
// It takes a `SpokenWord` rather than a resolved `audioUrls`, because which
// recording a word has is one question and the eight call sites were answering
// it separately — see `SpokenWord`.

import SwiftUI

struct PronunciationButton: View {
    /// What to say, and enough to find its recording.
    let subject: SpokenWord
    var size: CGFloat = 40
    /// The button's own ground. `tujiPaper2` reads against a plain paper page;
    /// sitting on an image hero — which is itself `tujiPaper2` — it needs the
    /// lighter step or it disappears into the picture's container.
    var ground: Color = .tujiPaper2
    /// Analytics only — set at call sites where the word id is public and
    /// worth attributing (word detail); nil elsewhere.
    var wordId: String?
    /// Where the catalogue's recordings come from, and the service that plays
    /// them. Defaulted `.shared` per ADR-0001.
    var catalogue: WordClipReading = CatalogueClips()
    var speech: SpeechService = .shared

    @Environment(SettingsStore.self) private var settings

    /// This button's own in-flight request, or nil when it has not started one.
    @State private var request: Int?

    private var effectiveVoice: SpeechService.Voice {
        .preferred(for: self.settings.current, language: self.subject.language)
    }

    /// Whether *this* button's clip is the one making noise.
    private var isPlaying: Bool {
        guard let request, let playback = speech.playback,
              playback.requestID == request
        else { return false }
        switch playback.phase {
        case .loading, .playing: return true
        case .finished, .failed: return false
        }
    }

    var body: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            AnalyticsService.shared.track(.pronounce, wordId: self.wordId)
            self.request = self.speech.play(
                urlString: self.subject.clip(
                    voice: self.effectiveVoice,
                    catalogue: self.catalogue
                ),
                fallbackText: self.subject.text,
                voice: self.effectiveVoice
            )
        } label: {
            ZStack {
                Rectangle().fill(self.isPlaying ? .tujiCurrent : self.ground)
                Image(systemName: "speaker.wave.2.fill")
                    .font(.tujiIcon(self.size * 0.38, weight: .semibold))
                    .foregroundStyle(.tujiInk)
            }
            .frame(width: self.size, height: self.size)
            // d1 is the state-change step: this is a ground swapping, not
            // something the user is meant to watch.
            .animation(Motion.ease(Motion.d1), value: self.isPlaying)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("發音"))
    }
}

#Preview {
    PronunciationButton(subject: .headword("tomato", language: .en))
        .environment(SettingsStore.shared)
}
