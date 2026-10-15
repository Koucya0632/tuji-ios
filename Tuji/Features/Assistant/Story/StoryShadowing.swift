// 情境故事 — 跟讀 on a spoken line: a mic under the speaker button, and what was
// heard inside the bubble.
//
// The feedback says what the recogniser caught, not how good the accent was —
// see `ShadowingScore`. Missed words are listed by name so the person knows
// which part to try again, and the transcript is shown so a wrong reading is
// visible rather than just a lower number.

import SwiftUI

struct ShadowingButton: View {
    let recorder: ShadowingRecorder
    let line: Int
    let target: String
    let language: TargetLanguage
    var size: CGFloat = 28
    var speech: SpeechService = .shared

    private var active: Bool {
        self.recorder.isActive(line: self.line)
    }

    var body: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            if self.active {
                self.recorder.stop()
            } else {
                self.speech.stop()
                Task { await self.recorder.start(line: self.line, target: self.target, language: self.language) }
            }
        } label: {
            ZStack {
                Rectangle().fill(self.active ? .tujiCurrent : .tujiPaper)
                Image(systemName: self.active ? "stop.fill" : "mic.fill")
                    .font(.tujiIcon(self.size * 0.38, weight: .semibold))
                    .foregroundStyle(.tujiInk)
            }
            .frame(width: self.size, height: self.size)
            .animation(Motion.ease(Motion.d1), value: self.active)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(self.active ? Text("停止跟讀") : Text("跟讀"))
    }
}

struct ShadowingFeedback: View {
    let recorder: ShadowingRecorder
    let line: Int
    let language: TargetLanguage

    @Environment(\.openURL) private var openURL

    var body: some View {
        if self.recorder.lineID == self.line {
            self.content
                .font(.tujiBodySm)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, Space.s1)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch self.recorder.phase {
        case .idle:
            EmptyView()
        case let .listening(heard):
            VStack(alignment: .leading, spacing: 2) {
                Text("正在聽…").foregroundStyle(.tujiInk2)
                if !heard.isEmpty {
                    Text(verbatim: heard).foregroundStyle(.tujiInk3)
                }
            }
        case .finishing:
            Text("正在聽…").foregroundStyle(.tujiInk2)
        case let .scored(score, heard):
            self.result(score, heard: heard)
        case .denied:
            VStack(alignment: .leading, spacing: Space.s1) {
                Text("跟讀需要麥克風和語音辨識的權限。").foregroundStyle(.tujiInk2)
                Button {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        self.openURL(url)
                    }
                } label: {
                    Text("打開設定").underline().foregroundStyle(.tujiInk)
                }
                .buttonStyle(.plain)
            }
        case .unavailable:
            Text("這台裝置不支援這個語言的語音辨識。").foregroundStyle(.tujiInk2)
        case .failed:
            Text("沒辦法開始錄音，請再試一次。").foregroundStyle(.tujiInk2)
        }
    }

    @ViewBuilder
    private func result(_ score: ShadowingScore, heard: String) -> some View {
        if heard.isEmpty {
            Text("沒有聽到聲音").foregroundStyle(.tujiInk2)
        } else {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: Space.s2) {
                    self.verdict(score.verdict)
                        .font(.tujiBodySm.weight(.semibold))
                        .foregroundStyle(.tujiInk)
                    Text(verbatim: "\(Int((score.ratio * 100).rounded()))%")
                        .font(.tujiBodySm.monospacedDigit())
                        .foregroundStyle(.tujiInk2)
                }
                if !score.missed.isEmpty {
                    Text("沒聽到：\(self.list(score))")
                        .foregroundStyle(.tujiAlert)
                }
                Text("聽到：\(heard)").foregroundStyle(.tujiInk3)
            }
        }
    }

    /// Missed phrases, listed the way the line's own language lists things.
    private func list(_ score: ShadowingScore) -> String {
        switch self.language {
        case .ja: score.missedPhrases(joiner: "").joined(separator: "\u{3001}")
        case .en: score.missedPhrases(joiner: " ").joined(separator: ", ")
        }
    }

    private func verdict(_ verdict: ShadowingScore.Verdict) -> Text {
        switch verdict {
        case .great: Text("很好！")
        case .close: Text("差不多了")
        case .again: Text("再試一次")
        }
    }
}
