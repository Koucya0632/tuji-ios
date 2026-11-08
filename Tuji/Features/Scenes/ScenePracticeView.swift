// 場面練習 itself: one 問句 at a time, then a summary. The screen renders
// `ScenePracticeSession.phase`; every decision about what comes next is there.

import SwiftUI

struct ScenePracticeView: View {
    let sceneId: SceneID
    let user: SessionUser?
    var catalog: SceneCatalog = .bundled

    @State private var session: ScenePracticeSession?
    @State private var showsTranscript = false
    @Environment(SettingsStore.self) private var settings
    @Environment(\.presentPaywall) private var presentPaywall
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            TujiNavBar(leading: .close) {
                if let position = self.session?.position {
                    Text(verbatim: "\(position.current) / \(position.total)")
                        .font(.tujiMono)
                        .foregroundStyle(.tujiInk3)
                }
            }
            if let session {
                switch session.phase {
                case let .practising(_, phase):
                    if let step = session.currentStep, let question = session.currentQuestion {
                        self.practising(session, step: step, question: question, phase: phase)
                    }
                case let .finished(summary):
                    self.finished(summary)
                }
            } else {
                Spacer()
            }
        }
        .background(.tujiPaper)
        .navigationTitle("場面練習")
        .toolbar(.hidden, for: .navigationBar)
        .task {
            guard self.session == nil, let user, let scene = self.catalog.scene(self.sceneId) else { return }
            SceneProgressStore.shared.use(account: user.id)
            self.session = ScenePracticeSession(scene: scene, store: .shared)
        }
        .task(id: self.session?.currentStep) {
            self.showsTranscript = false
            if let line = self.session?.currentStep?.phrasing.spoken {
                SceneAudio.play(line)
            }
        }
        .onDisappear { SpeechService.shared.stop() }
    }

    private var language: UILanguage {
        self.settings.current.uiLanguage
    }

    // MARK: - One 問句

    private func practising(
        _ session: ScenePracticeSession,
        step: PracticeStep,
        question: SceneQuestion,
        phase: ScenePracticeSession.QuestionPhase
    )
        -> some View
    {
        let tried: Set<String> = if case let .answeredWrong(tried) = phase { tried } else { [] }
        let revealed = if case .revealed = phase { true } else { false }
        return VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: Space.s4) {
                    VStack(alignment: .leading, spacing: Space.s1) {
                        Text(self.modeLabel(step.mode))
                            .font(.tujiLabel)
                            .tracking(2)
                            .foregroundStyle(.tujiInk3)
                        Text(verbatim: question.goal.resolved(self.language))
                            .font(.tujiH2)
                            .foregroundStyle(.tujiInk)
                    }
                    if let line = step.phrasing.spoken {
                        self.listenPanel(line, step: step, revealed: revealed)
                    }
                    if let screen = step.phrasing.screen {
                        ScreenMockView(
                            kind: screen,
                            tried: tried,
                            correctId: revealed ? question.correctChoice?.id : nil,
                            onTap: { session.answer($0) }
                        )
                    }
                    if question.kind == .listening {
                        self.choices(question, tried: tried, revealed: revealed, session: session)
                    }
                    if !tried.isEmpty, !revealed {
                        Text(question.kind == .listening ? "不是這個。再聽一次，然後再選。" : "不是這個。再看一次畫面。")
                            .font(.tujiBodySm)
                            .foregroundStyle(.tujiAlert)
                    }
                    if revealed {
                        self.reveal(question, step: step)
                    }
                }
                .padding(.horizontal, Space.s4)
                .padding(.top, Space.s2)
                .padding(.bottom, Space.s6)
            }
            if revealed {
                BBtn(
                    title: session.position?.current == session.position?.total ? "看結果" : "下一句",
                    fullWidth: true
                ) { session.next() }
                    .padding(.horizontal, Space.s4)
                    .padding(.vertical, Space.s3)
            }
        }
    }

    private func modeLabel(_ mode: PracticeMode) -> LocalizedStringKey {
        switch mode {
        case .first: "首練"
        case .review: "複習"
        case .rehearsal: "再練"
        }
    }

    /// Replay always; slow playback and the transcript only before a review,
    /// whose point is hearing it without them.
    private func listenPanel(_ line: SpokenLine, step: PracticeStep, revealed: Bool) -> some View {
        let helps = step.mode != .review
        return VStack(alignment: .leading, spacing: Space.s3) {
            HStack(spacing: Space.s2) {
                Text(step.phrasing.speaker.label)
                    .font(.tujiLabel)
                    .foregroundStyle(.tujiInk3)
                Spacer(minLength: 0)
                if helps {
                    ScenePlayButton(label: "慢速播放", systemImage: "tortoise.fill") {
                        SceneAudio.play(line, rate: 0.8)
                    }
                }
                ScenePlayButton(label: "再聽一次", systemImage: "arrow.counterclockwise") {
                    SceneAudio.play(line)
                }
            }
            if helps, !revealed {
                Toggle(isOn: self.$showsTranscript) {
                    Text("顯示日文")
                        .font(.tujiBodySm)
                        .foregroundStyle(.tujiInk2)
                }
                .tint(.tujiAccumulation)
            }
            if revealed || (helps && self.showsTranscript) {
                Text(verbatim: line.text)
                    .font(.tujiH3)
                    .foregroundStyle(.tujiInk)
            }
        }
        .padding(Space.s3)
        .background(.tujiPaper2)
    }

    private func choices(
        _ question: SceneQuestion,
        tried: Set<String>,
        revealed: Bool,
        session: ScenePracticeSession
    )
        -> some View
    {
        VStack(spacing: Space.s2) {
            ForEach(question.choices) { choice in
                let isTried = tried.contains(choice.id)
                let isAnswer = revealed && choice.correct
                Button { session.answer(choice.id) } label: {
                    Text(verbatim: choice.text.resolved(self.language))
                        .font(.tujiBody)
                        .foregroundStyle(isTried ? .tujiInk3 : .tujiInk)
                        .strikethrough(isTried)
                        .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
                        .padding(.horizontal, Space.s3)
                        .background(isAnswer ? .tujiBrandPrimary : .tujiPaper)
                        .overlay(Rectangle().stroke(isAnswer ? .tujiInk : .tujiRule, lineWidth: Border.bw2))
                }
                .buttonStyle(.plain)
                .disabled(isTried || revealed)
            }
        }
    }

    private func reveal(_ question: SceneQuestion, step: PracticeStep) -> some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            if question.kind == .screen,
               let screen = step.phrasing.screen,
               let correct = question.correctChoice,
               let label = screen.label(for: correct.id)
            {
                self.revealLine("該按") {
                    Text(verbatim: "\(label)（\(correct.text.resolved(self.language))）")
                }
            } else if let meaning = question.correctChoice {
                self.revealLine("意思") {
                    Text(verbatim: meaning.text.resolved(self.language))
                }
            }
            HStack(alignment: .center, spacing: Space.s3) {
                self.revealLine("回應") {
                    Text(verbatim: question.response.ja)
                }
                Spacer(minLength: 0)
                if question.response.clip != nil {
                    ScenePlayButton(label: "播放回應") { SceneAudio.play(question.response) }
                }
            }
            Text(verbatim: question.explanation.resolved(self.language))
                .font(.tujiBodySm)
                .foregroundStyle(.tujiInk2)
        }
        .padding(Space.s3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(Rectangle().stroke(.tujiInk, lineWidth: Border.bw2))
    }

    private func revealLine(_ title: LocalizedStringKey, @ViewBuilder value: () -> Text) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.tujiLabel)
                .foregroundStyle(.tujiInk3)
            value()
                .font(.tujiBody(.strong))
                .foregroundStyle(.tujiInk)
        }
    }

    // MARK: - Summary

    private func finished(_ summary: ScenePracticeSession.Summary) -> some View {
        ScrollView {
            TujiScreenTitle("練完了")
            VStack(alignment: .leading, spacing: Space.s4) {
                Text("這次練了 \(summary.practised) 句，第一次就答對 \(summary.firstTry) 句。")
                    .font(.tujiBody)
                    .foregroundStyle(.tujiInk)
                if let next = self.nextLine(summary.status) {
                    Text(next)
                        .font(.tujiBody)
                        .foregroundStyle(.tujiInk2)
                }
                VStack(alignment: .leading, spacing: Space.s3) {
                    Text("永久會員可以解鎖全部官方圖鑑，也能做自己的圖鑑。")
                        .font(.tujiBodySm)
                        .foregroundStyle(.tujiInk2)
                    BBtn(title: "看永久會員方案", fullWidth: true) { self.presentPaywall() }
                }
                .padding(Space.s3)
                .background(.tujiPaper2)
                BBtn(title: "回到場面", bg: .tujiPaper2, fullWidth: true) { self.dismiss() }
            }
            .padding(.horizontal, Space.s4)
            .padding(.bottom, Space.s6)
        }
    }

    private func nextLine(_ status: SceneStatus) -> LocalizedStringKey? {
        switch status {
        case .reviewLater: "明天會換個問法，再複習一次。"
        case .reviewDue, .inProgress: "還有沒練到的問句，下次從那裡繼續。"
        case .complete: "這個場面都複習過了。"
        case .notStarted: nil
        }
    }
}
