// What the 場面 screens say about progress, and how they play a line.

import SwiftUI

extension SceneStatus {
    var label: LocalizedStringKey {
        switch self {
        case .notStarted: "還沒練習"
        case let .inProgress(practised, total): "練過 \(practised)／\(total) 句"
        case let .reviewDue(count): "今天複習 \(count) 句"
        case .reviewLater: "明天複習"
        case .complete: "複習完了"
        }
    }

    var startTitle: LocalizedStringKey {
        switch self {
        case .notStarted: "開始練習"
        case .inProgress: "繼續練習"
        case .reviewDue: "開始複習"
        case .reviewLater, .complete: "再練一次"
        }
    }

    /// Something to practise today: the card's status line is set in ink.
    var isOwedToday: Bool {
        switch self {
        case .reviewDue, .inProgress: true
        case .notStarted, .reviewLater, .complete: false
        }
    }
}

extension Phrasing.Speaker {
    var label: LocalizedStringKey {
        switch self {
        case .clerk: "店員"
        case .register: "收銀機播報"
        case .screen: "畫面"
        }
    }
}

extension SceneQuestion {
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
    let action: () -> Void

    var body: some View {
        Button(action: self.action) {
            Image(systemName: self.systemImage)
                .font(.tujiIcon(17, weight: .semibold))
                .foregroundStyle(.tujiInk)
                .frame(width: 44, height: 44)
                .background(.tujiPaper2, in: .rect(cornerRadius: Radius.r0))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(self.label))
    }
}
