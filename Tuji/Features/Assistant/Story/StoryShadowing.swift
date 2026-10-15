// 情境故事 — 跟讀 on a spoken line: a mic under the speaker button, and the
// result inside the bubble.
//
// The result is one number — how much of the line the recogniser caught, not
// how good the accent was (see `ShadowingScore`) — and a button to hear the
// try back. The transcript is not shown: the person judges their own reading
// by listening to it beside the line's own voice.

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
    var speech: SpeechService = .shared

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
        case .listening, .finishing:
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
            HStack(spacing: Space.s3) {
                Text(verbatim: "\(Int((score.ratio * 100).rounded()))%")
                    .font(.tujiBody(.strong).monospacedDigit())
                    .foregroundStyle(.tujiInk)
                if self.recorder.recording != nil {
                    Button {
                        self.speech.stop()
                        self.recorder.playRecording()
                    } label: {
                        HStack(spacing: Space.s1) {
                            Image(systemName: self.recorder.isPlayingBack ? "stop.fill" : "play.fill")
                                .font(.tujiIcon(11, weight: .bold))
                            Text("聽我說的")
                        }
                        .font(.tujiBodySm(.strong))
                        .foregroundStyle(.tujiInk)
                        .frame(minHeight: 44)
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(self.recorder.isPlayingBack ? Text("停止播放") : Text("聽我說的"))
                }
            }
        }
    }
}
