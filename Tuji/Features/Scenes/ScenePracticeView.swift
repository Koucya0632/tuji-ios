// 場面練習 itself: one 問句 at a time, then a summary. The screen renders
// `ScenePracticeSession.phase`; every decision about what comes next is there.

import SwiftUI

struct ScenePracticeView: View {
    let sceneId: SceneID
    let user: SessionUser?
    var catalog: SceneCatalog = .bundled

    @State private var session: ScenePracticeSession?
    @State private var showsTranscript = false
    @State private var plays = 0
    @State private var openWord: CardWord?
    @Environment(SettingsStore.self) private var settings
    @Environment(WordsStore.self) private var words
    @Environment(\.dismiss) private var dismiss
    @Environment(StudyFocus.self) private var studyFocus

    var body: some View {
        VStack(spacing: 0) {
            if let session {
                switch session.phase {
                case let .practising(index, phase):
                    if let step = session.currentStep, let question = session.currentQuestion {
                        self.topBar(session, index: index, revealed: phase.isRevealed)
                        self.practising(session, step: step, question: question, phase: phase)
                    }
                case let .finished(summary):
                    SceneDoneView(scene: session.scene, summary: summary)
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
            self.plays = 0
            if let line = self.session?.currentStep?.phrasing.spoken {
                self.play(line)
            }
        }
        // Full screen like a study session: the tab bar goes while practising.
        .onAppear { self.studyFocus.enter() }
        .onDisappear {
            self.studyFocus.exit()
            SpeechService.shared.stop()
        }
        .tujiSheet(
            isPresented: Binding(get: { self.openWord != nil }, set: { if !$0 { self.openWord = nil } }),
            title: "單字詳情",
            height: 520
        ) {
            if let word = self.openWord {
                WordDetailSheet(word: word, wordId: word.id, gloss: word.chinese, audioUrls: word.audioUrls)
            }
        }
    }

    private var language: UILanguage {
        self.settings.current.uiLanguage
    }

    private func play(_ line: SpokenLine, rate: Float = 1) {
        self.plays += 1
        SceneAudio.play(line, rate: rate)
    }

    // MARK: - Top bar

    private func topBar(_ session: ScenePracticeSession, index: Int, revealed: Bool) -> some View {
        HStack(spacing: 12) {
            Button { self.dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.tujiIcon(18, weight: .bold))
                    .foregroundStyle(.tujiInk)
                    .frame(width: 44, height: 44)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(session.currentStep?.mode == .review ? "結束複習" : "結束練習"))
            SceneSegments(
                segments: session.steps.indices.map { step -> SceneSegments.Segment in
                    if step < index || (step == index && revealed) { return .done }
                    return step == index ? .current : .todo
                },
                spacing: 4
            )
            Text(verbatim: "\(index + 1) / \(session.steps.count)")
                .font(.tujiLabel)
                .foregroundStyle(.tujiInk2)
                .frame(minWidth: 32, alignment: .trailing)
        }
        .padding(.leading, Space.s2)
        .padding(.trailing, Space.s3)
        .frame(height: 44)
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
        let revealed = phase.isRevealed
        return VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    switch question.kind {
                    case .listening:
                        if revealed {
                            self.revealPanel(question, step: step)
                        } else if let line = step.phrasing.spoken {
                            self.listenPanel(line, step: step)
                        }
                        Text(step.phrasing.speaker.asking)
                            .font(.tujiH3)
                            .foregroundStyle(.tujiInk)
                            .padding(.horizontal, Space.s2)
                            .padding(.top, 20)
                        self.choices(question, step: step, tried: tried, revealed: revealed, session: session)
                            .padding(.top, Space.s3)
                    case .screen:
                        self.screenQuestion(question, step: step, tried: tried, revealed: revealed, session: session)
                    }
                }
                .padding(.horizontal, Space.s3)
                .padding(.top, Space.s3)
                .padding(.bottom, Space.s4)
            }
            if revealed {
                let last = session.position?.current == session.position?.total
                Button { session.next() } label: {
                    HStack {
                        Text(last ? "看結果" : "下一句").font(.tujiH3)
                        Spacer()
                        Image(systemName: "arrow.right").font(.tujiIcon(18, weight: .bold))
                    }
                    .foregroundStyle(.tujiInk)
                    .padding(.vertical, Space.s3)
                    .padding(.horizontal, 20)
                    .background(.tujiCurrent)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, Space.s3)
                .padding(.bottom, Space.s3)
            }
        }
    }

    /// Before the answer: the replay button, how often it was heard, and for
    /// first practice slow playback and the transcript. A review has none of
    /// those helps, and says what is new about this phrasing instead.
    private func listenPanel(_ line: SpokenLine, step: PracticeStep) -> some View {
        let review = step.mode == .review
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: step.phrasing.speaker.symbol).font(.tujiIcon(13, weight: .semibold))
                Text(step.phrasing.speaker.label).font(.tujiLabel)
                Spacer()
                if review { Text("複習").font(.tujiLabel) }
            }
            .foregroundStyle(.tujiInk2)
            if review {
                HStack(spacing: 6) {
                    self.reviewLabel("沒聽過的問法")
                    if step.phrasing.speed == .fast { self.reviewLabel("語速快") }
                    if step.phrasing.ambience { self.reviewLabel("店內環境音") }
                }
                .padding(.top, 10)
            }
            VStack(spacing: 12) {
                Button { self.play(line) } label: {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.tujiIcon(32, weight: .bold))
                        .foregroundStyle(review ? .tujiInk : .tujiPaper)
                        .frame(width: 88, height: 88)
                        .background(review ? .tujiCurrent : .tujiInk)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("再聽一次"))
                if self.showsTranscript {
                    Text(verbatim: line.text)
                        .font(.scene(19))
                        .foregroundStyle(.tujiInk)
                        .multilineTextAlignment(.center)
                } else if review {
                    Text("再聽一次").font(.tujiLabel).foregroundStyle(.tujiInk)
                } else {
                    Text("聽過 \(self.plays) 次").font(.scene(13, bold: false)).foregroundStyle(.tujiInk2)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 190)
            if !review {
                HStack(spacing: Space.s2) {
                    self.pill("慢速", pressed: false) { self.play(line, rate: 0.8) }
                    self.pill("顯示日文", pressed: self.showsTranscript) { self.showsTranscript.toggle() }
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(18)
        .frame(minHeight: 298, alignment: .top)
        .background(.tujiPaper2)
    }

    private func reviewLabel(_ title: LocalizedStringKey) -> some View {
        Text(title)
            .font(.tujiLabel)
            .foregroundStyle(.tujiInk2)
            .padding(.horizontal, Space.s2)
            .padding(.vertical, 2)
            .background(.tujiPaper)
            .overlay(Rectangle().strokeBorder(.tujiRule, lineWidth: 1))
    }

    private func pill(_ title: LocalizedStringKey, pressed: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.tujiLabel)
                .foregroundStyle(pressed ? .tujiPaper : .tujiInk2)
                .padding(.horizontal, Space.s3)
                .frame(height: 36)
                .background(pressed ? Color.tujiInk : Color.tujiPaper, in: .capsule)
                .overlay(Capsule().strokeBorder(.tujiRule, lineWidth: 1))
                .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(pressed ? .isSelected : [])
    }

    private func choices(
        _ question: SceneQuestion,
        step: PracticeStep,
        tried: Set<String>,
        revealed: Bool,
        session: ScenePracticeSession
    )
        -> some View
    {
        let letters = ["A", "B", "C", "D"]
        let ordered = question.choices(for: step.phrasing.id)
        let shown = revealed ? ordered.filter(\.correct) : ordered
        return VStack(spacing: Space.s2) {
            ForEach(shown) { choice in
                let letter = letters[ordered.firstIndex(of: choice) ?? 0]
                let isTried = tried.contains(choice.id)
                Button { session.answer(choice.id) } label: {
                    HStack(spacing: Space.s3) {
                        Text(verbatim: letter)
                            .font(.tujiLabel)
                            .foregroundStyle(revealed ? .tujiInk : .tujiInk2)
                            .frame(width: 32, height: 32)
                            .background(revealed ? .tujiCurrent : .tujiPaper3)
                        Text(verbatim: choice.text.resolved(self.language))
                            .font(.tujiH3)
                            .foregroundStyle(revealed ? .tujiPaper : isTried ? .tujiInk3 : .tujiInk)
                            .multilineTextAlignment(.leading)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, Space.s3)
                    .padding(.vertical, 10)
                    .frame(minHeight: 64)
                    .background(revealed ? .tujiInk : .tujiPaper2)
                    .overlay(Rectangle().strokeBorder(
                        revealed ? .tujiAccumulation : isTried ? .tujiAlert : .clear,
                        lineWidth: 3
                    ))
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .allowsHitTesting(!isTried && !revealed)
                .accessibilityValue(isTried ? Text("答錯") : revealed ? Text("正確") : Text(verbatim: ""))
            }
        }
    }
}

extension ScenePracticeView {
    // MARK: - Screen question

    private func screenQuestion(
        _ question: SceneQuestion,
        step: PracticeStep,
        tried: Set<String>,
        revealed: Bool,
        session: ScenePracticeSession
    )
        -> some View
    {
        VStack(alignment: .leading, spacing: 0) {
            if let line = step.phrasing.spoken {
                VStack(alignment: .leading, spacing: Space.s2) {
                    HStack(spacing: 12) {
                        Button { self.play(line) } label: {
                            Image(systemName: "arrow.counterclockwise")
                                .font(.tujiIcon(18, weight: .bold))
                                .foregroundStyle(.tujiPaper)
                                .frame(width: 48, height: 48)
                                .background(.tujiInk)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(Text("重播店員的話"))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(step.phrasing.speaker.label).font(.tujiLabel).foregroundStyle(.tujiInk2)
                            Text("聽過 \(self.plays) 次").font(.scene(13, bold: false)).foregroundStyle(.tujiInk3)
                        }
                        Spacer(minLength: 0)
                        if step.mode != .review, !revealed {
                            self.pill("顯示日文", pressed: self.showsTranscript) {
                                self.showsTranscript.toggle()
                            }
                        }
                    }
                    if self.showsTranscript || revealed {
                        Text(verbatim: line.text)
                            .font(.tujiH3)
                            .foregroundStyle(.tujiInk)
                    }
                }
                .padding(14)
                .background(.tujiPaper2)
            }
            VStack(alignment: .leading, spacing: Space.s1) {
                Text(verbatim: question.goal.resolved(self.language))
                    .font(.scene(13, bold: false))
                    .foregroundStyle(.tujiInk2)
                Text(Phrasing.Speaker.screen.asking)
                    .font(.tujiH3)
                    .foregroundStyle(.tujiInk)
            }
            .padding(.horizontal, Space.s2)
            .padding(.top, 20)
            if let screen = step.phrasing.screen {
                ScreenMockView(
                    screen: screen,
                    tried: tried,
                    correctId: revealed ? question.correctChoice?.id : nil,
                    onTap: { session.answer($0) }
                )
                .padding(.top, Space.s3)
            }
            Text("畫面依店家不同")
                .font(.scene(13, bold: false))
                .foregroundStyle(.tujiInk3)
                .padding(.horizontal, Space.s2)
                .padding(.top, 12)
            if revealed {
                self.revealPanel(question, step: step)
                    .padding(.top, Space.s3)
            }
        }
    }

    // MARK: - Reveal

    private func revealPanel(_ question: SceneQuestion, step: PracticeStep) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if question.kind == .listening, let line = step.phrasing.spoken {
                HStack(spacing: 6) {
                    Image(systemName: step.phrasing.speaker.symbol).font(.tujiIcon(13, weight: .semibold))
                    Text(step.phrasing.speaker.label).font(.tujiLabel)
                    if step.phrasing.speaker == .register {
                        Text("· 機器自動播報").font(.scene(13, bold: false)).foregroundStyle(.tujiInk3)
                    }
                }
                .foregroundStyle(.tujiInk2)
                HStack(spacing: Space.s1) {
                    Text(verbatim: line.text)
                        .font(.scene(19))
                        .foregroundStyle(.tujiInk)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    ScenePlayButton(label: "重播", systemImage: "arrow.counterclockwise", fill: .tujiPaper) {
                        self.play(line)
                    }
                }
                .padding(.top, Space.s2)
            }
            if question.kind == .screen,
               let screen = step.phrasing.screen,
               let correct = question.correctChoice,
               let label = screen.label(for: correct.id)
            {
                Text("按「\(label)」")
                    .font(.scene(19))
                    .foregroundStyle(.tujiInk)
            }
            if let meaning = question.correctChoice?.text {
                Text(verbatim: meaning.resolved(self.language))
                    .font(.tujiBodySm(.strong))
                    .foregroundStyle(.tujiInk2)
            }
            Text(verbatim: question.explanation.resolved(self.language))
                .font(.scene(13, bold: false))
                .foregroundStyle(.tujiInk2)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, Space.s2)
                .padding(.trailing, 10)
            self.rule
            Text("你可以回")
                .font(.scene(13, bold: false))
                .foregroundStyle(.tujiInk3)
            HStack(spacing: Space.s2) {
                Text(verbatim: question.response.ja)
                    .font(.tujiBody(.strong))
                    .foregroundStyle(.tujiInk)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if question.response.clip != nil {
                    ScenePlayButton(label: "播放回應", fill: nil) { SceneAudio.play(question.response) }
                }
            }
            .frame(minHeight: 44)
            let words = question.relatedWords(in: self.words, direction: self.settings.current.learningDirection)
            if !words.isEmpty {
                self.rule
                SceneWordList(words: words, opening: .present { self.openWord = $0 })
                    .padding(.trailing, 10)
            }
        }
        .padding(.top, Space.s3)
        .padding(.leading, 18)
        .padding(.trailing, Space.s2)
        .padding(.bottom, Space.s2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.tujiPaper2)
    }

    private var rule: some View {
        Rectangle()
            .fill(.tujiRule)
            .frame(height: 1)
            .padding(.trailing, 10)
            .padding(.vertical, 10)
    }
}

extension ScenePracticeSession.QuestionPhase {
    var isRevealed: Bool {
        if case .revealed = self { true } else { false }
    }
}
