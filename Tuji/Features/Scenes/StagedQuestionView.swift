// One 問句 on a staged 場面 (SCENE_PRACTICE_IMMERSIVE_DESIGN.md): the photo
// says where the traveller stands, props sit on the counter, and the panel
// at the bottom is where they listen and act. A listening 問句 is answered
// by picking what to say back; a screen 問句 by working the machine.
//
// The view is rebuilt for every 問句 (`.id` on the step), so the machine, the
// last reply and the play count start fresh with it.

import SwiftUI

struct StagedQuestionView: View {
    let session: ScenePracticeSession
    let step: PracticeStep
    let question: SceneQuestion
    let stage: StageStep
    let phase: ScenePracticeSession.QuestionPhase
    let route: StageRoute
    /// False until the traveller walks in; nothing plays before that.
    let entered: Bool
    let onEnter: () -> Void
    let openWord: (CardWord) -> Void

    @Environment(SettingsStore.self) private var settings
    @Environment(WordsStore.self) private var words
    @State private var line: SpokenLine?
    @State private var plays = 0
    @State private var subtitles = false
    @State private var chosen: StageReply?
    @State private var machine: SceneMachine?
    /// The panel's natural height; it scrolls only past what the photo can spare.
    @State private var lowerHeight: CGFloat = 0

    private var language: UILanguage {
        self.settings.current.uiLanguage
    }

    private var revealed: Bool {
        self.phase.isRevealed
    }

    var body: some View {
        GeometryReader { geo in
            VStack(spacing: 0) {
                ZStack(alignment: .topLeading) {
                    StageBackdropView(background: self.stage.background, props: self.shownProps, card: self.stage.card)
                    if self.entered, let note = self.stage.note {
                        Text(verbatim: note.resolved(self.language))
                            .font(.tujiBodySm(.strong))
                            .foregroundStyle(.tujiPaper)
                            .padding(.horizontal, Space.s3)
                            .padding(.vertical, Space.s2)
                            .background(.tujiInk.opacity(0.78))
                            .padding(Space.s3)
                    }
                }
                .frame(minHeight: 150, maxHeight: .infinity)
                ScrollView {
                    self.lower
                        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { self.lowerHeight = $0 }
                }
                .scrollBounceBehavior(.basedOnSize)
                .defaultScrollAnchor(.bottom)
                .frame(height: min(self.lowerHeight, max(200, geo.size.height - 150)))
                .background(.tujiPaper)
            }
        }
        .task(id: self.entered) {
            if self.machine == nil, let kind = self.stage.machine {
                self.machine = kind.makeMachine()
            }
            if self.entered, self.line == nil, let line = self.step.phrasing.spoken {
                self.play(line)
            }
        }
    }

    @ViewBuilder
    private var lower: some View {
        if self.entered {
            self.panel
        } else {
            self.enterCard
        }
    }

    /// Before anything plays: what the traveller is here to do, and the step in.
    private var enterCard: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            Text("這一次")
                .font(.tujiLabel)
                .tracking(1)
                .foregroundStyle(.tujiInk2)
            Text(verbatim: self.route.intent.resolved(self.language))
                .font(.tujiH3)
                .foregroundStyle(.tujiInk)
                .fixedSize(horizontal: false, vertical: true)
            Button(action: self.onEnter) {
                HStack {
                    Text(verbatim: self.route.enter.resolved(self.language)).font(.tujiH3)
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
        }
        .padding(Space.s3)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var shownProps: [String] {
        let props = self.stage.props ?? []
        let extra = self.chosen?.show ?? []
        return props + extra.filter { !props.contains($0) }
    }

    private func play(_ line: SpokenLine, rate: Float = 1) {
        self.line = line
        self.plays += 1
        SceneAudio.play(line, rate: rate)
    }

    // MARK: - Panel

    private var panel: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            switch self.question.kind {
            case .listening:
                self.listening
            case .screen:
                self.screen
            }
            if self.revealed {
                self.reveal
                Button { self.session.next() } label: {
                    HStack {
                        Text(self.session.position?.current == self.session.position?.total ? "看結果" : "下一句")
                            .font(.tujiH3)
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
            }
        }
        .padding(Space.s3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.tujiPaper)
    }

    // MARK: Listening

    @ViewBuilder
    private var listening: some View {
        let shown = self.line ?? self.step.phrasing.spoken
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack(spacing: 6) {
                Image(systemName: self.step.phrasing.speaker.symbol).font(.tujiIcon(13, weight: .semibold))
                Text(self.step.phrasing.speaker.label).font(.tujiLabel)
                if self.step.mode == .review {
                    Text(verbatim: "·").font(.tujiLabel)
                    Text("複習").font(.tujiLabel)
                }
                Spacer()
                Text("聽過 \(self.plays) 次").font(.scene(13, bold: false))
            }
            .foregroundStyle(.tujiInk2)
            if let shown, self.subtitles || self.revealed {
                Text(verbatim: shown.text)
                    .font(.scene(19))
                    .foregroundStyle(.tujiInk)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Space.s2) {
                    if let original = self.step.phrasing.spoken {
                        self.pill("重聽", systemImage: "arrow.counterclockwise") { self.play(original) }
                    }
                    if !self.revealed {
                        self.pill("請再說一次", systemImage: "bubble.left") {
                            if let again = self.session.askAgain() { self.play(again) }
                        }
                        if let shown {
                            self.pill("慢速", systemImage: "tortoise") {
                                self.session.noteHint()
                                self.play(shown, rate: 0.8)
                            }
                        }
                        self.pill("字幕", systemImage: "captions.bubble", pressed: self.subtitles) {
                            self.subtitles.toggle()
                            if self.subtitles { self.session.noteHint() }
                        }
                    }
                }
            }
        }
        if !self.revealed {
            self.replies
        }
    }

    private var replies: some View {
        let tried: Set<String> = if case let .answeredWrong(tried) = self.phase { tried } else { [] }
        return VStack(alignment: .leading, spacing: Space.s2) {
            if let chosen, tried.contains("reply:" + chosen.id) {
                self.result(chosen.result, fits: false)
            }
            Text(self.stage.replies?.contains { !$0.isSpoken } == true ? "你要怎麼做？" : "你要怎麼回？")
                .font(.tujiH3)
                .foregroundStyle(.tujiInk)
            ForEach(self.stage.replies(for: self.step.phrasing.id)) { reply in
                let missed = tried.contains("reply:" + reply.id)
                Button {
                    self.chosen = reply
                    if reply.isSpoken { SceneAudio.say(reply) }
                    self.session.reply(reply)
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        if reply.isSpoken {
                            Text(verbatim: reply.ja)
                                .font(.tujiH3)
                                .foregroundStyle(missed ? .tujiInk3 : .tujiInk)
                            Text(verbatim: reply.meaning.resolved(self.language))
                                .font(.scene(13, bold: false))
                                .foregroundStyle(.tujiInk2)
                        } else {
                            Text(verbatim: reply.meaning.resolved(self.language))
                                .font(.tujiH3)
                                .foregroundStyle(missed ? .tujiInk3 : .tujiInk)
                        }
                    }
                    .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
                    .padding(.horizontal, Space.s3)
                    .padding(.vertical, Space.s2)
                    .background(.tujiPaper2)
                    .overlay(Rectangle().strokeBorder(missed ? .tujiAlert : .clear, lineWidth: 3))
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .allowsHitTesting(!missed)
                .accessibilityValue(missed ? Text("答錯") : Text(verbatim: ""))
            }
        }
    }

    // MARK: Screen

    @ViewBuilder
    private var screen: some View {
        let tried: Set<String> = if case let .answeredWrong(tried) = self.phase { tried } else { [] }
        if let spoken = self.step.phrasing.spoken {
            VStack(alignment: .leading, spacing: Space.s2) {
                HStack(spacing: Space.s2) {
                    Image(systemName: self.step.phrasing.speaker.symbol).font(.tujiIcon(13, weight: .semibold))
                    Text(self.step.phrasing.speaker.label).font(.tujiLabel)
                    Spacer()
                    self.pill("重聽", systemImage: "arrow.counterclockwise") { self.play(spoken) }
                    self.pill("字幕", systemImage: "captions.bubble", pressed: self.subtitles || self.revealed) {
                        self.subtitles.toggle()
                        if self.subtitles { self.session.noteHint() }
                    }
                }
                .foregroundStyle(.tujiInk2)
                if self.subtitles || self.revealed {
                    Text(verbatim: spoken.text)
                        .font(.tujiBody(.strong))
                        .foregroundStyle(.tujiInk)
                }
            }
        }
        if let spec = self.stage.machine, let machine = self.machine {
            MachineView(machine: machine, brandOverride: spec.brand) { action in
                guard var next = self.machine else { return }
                next.send(action)
                self.machine = next
                if let outcome = next.outcome {
                    self.session.finish(outcome, fits: spec.fits(outcome))
                }
            }
            if !tried.isEmpty, !self.revealed {
                self.result(self.question.goal, fits: false)
                Button {
                    self.machine = spec.makeMachine()
                } label: {
                    Label("重來", systemImage: "arrow.counterclockwise")
                        .font(.tujiBody(.strong))
                        .foregroundStyle(.tujiInk)
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .background(.tujiPaper2)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
            }
        } else if let screen = self.step.phrasing.screen {
            Text(verbatim: self.question.goal.resolved(self.language))
                .font(.scene(13, bold: false))
                .foregroundStyle(.tujiInk2)
            ScreenMockView(
                screen: screen,
                tried: tried,
                correctId: self.revealed ? self.question.correctChoice?.id : nil,
                onTap: { self.session.answer($0) }
            )
        }
    }

    // MARK: Reveal

    private var reveal: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            if let chosen {
                self.result(chosen.result, fits: true)
            }
            if let meaning = self.question.meaning {
                Text(verbatim: meaning.resolved(self.language))
                    .font(.tujiBodySm(.strong))
                    .foregroundStyle(.tujiInk2)
            }
            Text(verbatim: self.question.explanation.resolved(self.language))
                .font(.scene(13, bold: false))
                .foregroundStyle(.tujiInk2)
                .fixedSize(horizontal: false, vertical: true)
            let related = self.question.relatedWords(in: self.words, direction: self.settings.current.learningDirection)
            if !related.isEmpty {
                SceneWordList(words: related, opening: .present(self.openWord))
            }
        }
    }

    /// What happened after the traveller acted: plain when it went the way
    /// the trip wanted, marked when they should try again.
    private func result(_ text: LocalizedText, fits: Bool) -> some View {
        HStack(alignment: .top, spacing: Space.s2) {
            Rectangle().fill(fits ? .tujiAccumulation : .tujiAlert).frame(width: 3)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: text.resolved(self.language))
                    .font(.tujiBody(.strong))
                    .foregroundStyle(.tujiInk)
                if !fits {
                    Text("這不是這次想要的。再試一次。")
                        .font(.scene(13, bold: false))
                        .foregroundStyle(.tujiInk2)
                }
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private func pill(
        _ title: LocalizedStringKey,
        systemImage: String,
        pressed: Bool = false,
        action: @escaping () -> Void
    )
        -> some View
    {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.tujiLabel)
                .foregroundStyle(pressed ? .tujiPaper : .tujiInk2)
                .padding(.horizontal, 12)
                .frame(height: 36)
                .background(pressed ? Color.tujiInk : Color.tujiPaper2, in: .capsule)
                .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(pressed ? .isSelected : [])
    }
}

/// The names VoiceOver reads for the props on the counter.
enum StageProp {
    private static let labels: [String: LocalizedStringKey] = [
        "prop-bento": "便當",
        "prop-utensils": "餐具",
        "prop-bag": "購物袋",
        "prop-loyalty-card": "集點卡",
        "prop-credit-card": "信用卡",
        "prop-receipt": "收據",
        "prop-menu": "菜單",
        "prop-bill": "帳單"
    ]

    static func label(_ asset: String) -> LocalizedStringKey {
        self.labels[asset] ?? "道具"
    }
}
