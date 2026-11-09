// What the 場面 screens say about progress, and how they play a line.

import SwiftUI

extension SceneStatus {
    /// The scene page's call to action.
    var startTitle: LocalizedStringKey {
        switch self {
        case .notStarted: "開始練習"
        case .inProgress: "繼續練習"
        case .reviewDue: "開始複習"
        case .reviewLater, .complete: "再練一次"
        }
    }
}

extension Phrasing.Speaker {
    var label: LocalizedStringKey {
        switch self {
        case .clerk: "店員"
        case .register: "收銀機"
        case .screen: "螢幕"
        }
    }

    /// The practice screen's question over the choices.
    var asking: LocalizedStringKey {
        switch self {
        case .clerk: "店員在問什麼？"
        case .register: "收銀機在問什麼？"
        case .screen: "畫面上要按哪一個？"
        }
    }

    var symbol: String {
        switch self {
        case .clerk: "person.fill"
        case .register: "printer.fill"
        case .screen: "rectangle.portrait"
        }
    }
}

extension SceneQuestion {
    /// Who asks it as 進店前看一眼 shows it: whoever speaks the look line, or
    /// the screen when nothing is said.
    var lookSpeaker: Phrasing.Speaker {
        (self.phrasings.filter { $0.role == .first } + self.phrasings.filter { $0.role == .review })
            .first { $0.spoken != nil }?.speaker ?? .screen
    }

    /// What the question means, in the user's language.
    var meaning: LocalizedText? {
        self.kind == .listening ? self.correctChoice?.text : self.goal
    }

    /// The line 進店前看一眼 shows and plays: the first practice's, or for a
    /// screen with nothing said over it, the first phrasing that does speak.
    var lookLine: SpokenLine? {
        (self.phrasings.filter { $0.role == .first } + self.phrasings.filter { $0.role == .review })
            .lazy.compactMap(\.spoken).first
    }

    var correctChoice: SceneChoice? {
        self.choices.first(where: \.correct)
    }
}

@MainActor
enum SceneAudio {
    /// A bundled clip, or on-device synthesis while the clip does not exist yet.
    @discardableResult
    static func play(_ line: SpokenLine, rate: Float = 1) -> Int {
        SpeechService.shared.play(
            bundledFile: SceneCatalog.audioURL(line.audio),
            fallbackText: line.text,
            voice: .japanese,
            rate: rate
        )
    }

    /// A reply the traveller says on a staged 問句. Replies have no clip yet,
    /// so the device reads them.
    static func say(_ reply: StageReply) {
        SpeechService.shared.play(bundledFile: nil, fallbackText: reply.ja, voice: .japanese)
    }

    static func play(_ response: SceneResponse) {
        guard let clip = response.clip else { return }
        SpeechService.shared.play(
            bundledFile: SceneCatalog.audioURL(clip.audio),
            fallbackText: response.ja,
            voice: .japanese
        )
    }
}

/// The square speaker button the 場面 screens use for every line.
struct ScenePlayButton: View {
    let label: LocalizedStringKey
    var systemImage = "speaker.wave.2.fill"
    var fill: Color? = .tujiPaper2
    let action: () -> Void

    var body: some View {
        Button(action: self.action) {
            Image(systemName: self.systemImage)
                .font(.tujiIcon(17, weight: .semibold))
                .foregroundStyle(.tujiInk)
                .frame(width: 44, height: 44)
                .background(self.fill ?? .clear)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(self.label))
    }
}

/// One segment per question: practised, the one on screen, still to come.
struct SceneSegments: View {
    enum Segment {
        case done
        case current
        case todo
    }

    let segments: [Segment]
    var onInk = false
    var height: CGFloat = 4
    var spacing: CGFloat = 3

    var body: some View {
        HStack(spacing: self.spacing) {
            ForEach(Array(self.segments.enumerated()), id: \.offset) { _, segment in
                Rectangle().fill(self.color(segment)).frame(height: self.height)
            }
        }
        .accessibilityHidden(true)
    }

    private func color(_ segment: Segment) -> Color {
        switch (segment, self.onInk) {
        case (.done, false): .tujiAccumulation
        case (.done, true): .tujiAccumulationSoft
        case (.current, _): .tujiCurrent
        case (.todo, false): .tujiPaper3
        case (.todo, true): .tujiPaper.opacity(0.2)
        }
    }

    init(practised: [Bool], onInk: Bool = false, height: CGFloat = 4, spacing: CGFloat = 3) {
        self.segments = practised.map { $0 ? .done : .todo }
        self.onInk = onInk
        self.height = height
        self.spacing = spacing
    }

    init(segments: [Segment], spacing: CGFloat = 3) {
        self.segments = segments
        self.spacing = spacing
    }
}

/// 店員／收銀機／螢幕 over a line.
struct SceneSpeakerTag: View {
    let speaker: Phrasing.Speaker

    var body: some View {
        Text(self.speaker.label)
            .font(.tujiLabel)
            .foregroundStyle(.tujiInk2)
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
            .background(.tujiPaper2)
    }
}

extension PracticeScene {
    func practised(in book: SceneProgressBook) -> [Bool] {
        self.questions.map { book.progress($0.id).stage != .new }
    }
}

extension Font {
    /// The 場面 screens' sizes the type scale has no step for (20, 19, 15),
    /// in the app's faces.
    static func scene(_ size: CGFloat, bold: Bool = true) -> Font {
        TujiTypeface.font(latin: bold ? "PlusJakartaSans-Bold" : "PlusJakartaSans-Regular", size: size)
    }
}
