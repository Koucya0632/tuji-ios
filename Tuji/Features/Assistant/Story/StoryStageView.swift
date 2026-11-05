import SwiftUI

struct StoryStageView: View {
    let story: Story?
    let sceneId: String?
    let language: TargetLanguage
    let picked: [CardWord]
    let writing: StoryBuilderModel.Writing
    let close: () -> Void
    var speech: SpeechService = .shared

    @Environment(SettingsStore.self) private var settings
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Segments shown so far; 0 is the opening.
    @State private var shown = 0
    /// Past the last segment: the ending is up.
    @State private var ended = false
    /// Characters of the current box text typed so far.
    @State private var typed = Int.max
    @State private var typing: Task<Void, Never>?
    @State private var translating = false
    @State private var backlog = false
    @State private var practicing = false
    @State private var recorder = ShadowingRecorder()

    private var segments: [Story.Segment] {
        self.story?.segments ?? []
    }

    private var current: Story.Segment? {
        self.shown > 0 && self.shown <= self.segments.count ? self.segments[self.shown - 1] : nil
    }

    private var caughtUp: Bool {
        self.shown >= self.segments.count
    }

    private var finished: Bool {
        self.caughtUp && self.writing != .writing
    }

    private var isIllustrated: Bool {
        self.sceneId.flatMap(StoryStagePresentation.Scene.init(rawValue:)) != nil
    }

    private var presentation: StoryStagePresentation {
        .init(
            scene: self.sceneId.flatMap(StoryStagePresentation.Scene.init(rawValue:)) ?? .supermarket,
            segment: self.current
        )
    }

    var body: some View {
        GeometryReader { geo in
            if self.isIllustrated {
                StoryStageLayout(
                    presentation: self.presentation, reduceMotion: self.reduceMotion, advance: self.tap
                ) {
                    if self.ended {
                        self.ending(maxHeight: geo.size.height * 0.45)
                    } else {
                        self.dialogueBox(maxHeight: geo.size.height * 0.45)
                    }
                }
                .overlay(alignment: .top) { self.topBar }
            } else {
                ZStack(alignment: .bottom) {
                    StoryBackdrop(sceneId: self.sceneId)
                    self.moira(in: geo.size)
                    // The tap that moves on lives on its own layer and on the box,
                    // never on the whole stack, so the chips and the box's own
                    // buttons do not also advance the story.
                    Color.clear
                        .contentShape(.rect)
                        .onTapGesture { self.tap() }
                    VStack(spacing: Space.s2) {
                        Spacer(minLength: 0)
                        if self.ended {
                            self.ending(maxHeight: geo.size.height * 0.45)
                        } else {
                            self.box
                                .contentShape(.rect)
                                .onTapGesture { self.tap() }
                        }
                    }
                    .padding(.horizontal, Space.s3)
                    .padding(.bottom, Space.s3)
                    self.topBar
                        .frame(maxHeight: .infinity, alignment: .top)
                }
            }
        }
        .clipped()
        .sheet(isPresented: self.$backlog) { self.backlogSheet }
        .sheet(isPresented: self.$practicing, onDismiss: self.stopPractice) {
            if let current = self.current {
                StoryPracticeSheet(
                    segment: current, line: self.shown - 1, language: self.language, recorder: self.recorder
                )
            }
        }
        .onAppear { self.prepareStage() }
        .onChange(of: self.story?.intro) { self.typeOut() }
        .onDisappear {
            self.typing?.cancel()
            self.speech.stop()
            self.recorder.cancel()
        }
    }

    // MARK: - Moira

    private var pose: MascotPose {
        if self.finished, self.shown == self.segments.count, !self.segments.isEmpty { return .cheer }
        let last = self.segments.prefix(self.shown).last { $0.speaker != .narrator }
        switch last?.speaker {
        case .you: return .think
        default: return .wave
        }
    }

    private func moira(in size: CGSize) -> some View {
        let height = min(size.height * 0.46, size.width * 0.80)
        let pose = self.pose
        let groundY = size.height * StoryBackdrop.floor + height * 0.10
        return Mascot(pose: pose, size: height)
            .id(pose)
            .offset(y: groundY - height * pose.groundLine - (size.height - height) / 2)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .animation(Motion.ease(Motion.d2, reduceMotion: self.reduceMotion), value: pose)
            .accessibilityLabel(Text(verbatim: "Moira"))
    }

    // MARK: - Box

    private func dialogueBox(maxHeight: CGFloat) -> some View {
        StoryDialogue(
            name: self.name,
            isReader: self.current?.speaker == .you,
            maxHeight: maxHeight,
            contentKey: self.shown
        ) {
            VStack(alignment: .leading, spacing: Space.s2) {
                if let current = self.current {
                    if current.speaker == .narrator {
                        Text(verbatim: self.typedPart(current.text))
                            .font(.tujiBody)
                            .foregroundStyle(.tujiInk2)
                    } else {
                        self.lineText(current)
                        if self.translating, let translation = current.translation, self.typed == .max {
                            Text(verbatim: translation).font(.tujiBodySm).foregroundStyle(.tujiInk2)
                        }
                    }
                } else if let story = self.story {
                    Text(verbatim: self.typedPart(story.intro)).font(.tujiBody).foregroundStyle(.tujiInk)
                } else {
                    self.waiting
                }
            }
            .contentShape(.rect)
            .onTapGesture { self.tap() }
        } controls: {
            StoryStageControls(
                segment: self.current, translating: self.$translating,
                waiting: self.caughtUp && self.writing == .writing,
                replay: {
                    guard let current = self.current else { return }
                    self.recorder.cancel()
                    self.speech.speak(
                        current.text,
                        voice: .preferred(for: self.settings.current, language: self.language)
                    )
                },
                practice: {
                    self.stopPractice()
                    self.practicing = true
                },
                advance: self.tap
            )
        }
    }

    private var name: String? {
        guard let current else { return self.story?.title }
        switch current.speaker {
        case .cat: return "Moira"
        case .you: return tujiLocalized("你")
        case .narrator: return nil
        }
    }

    private var box: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let name {
                Text(verbatim: name)
                    .font(.tujiBodySm(.strong))
                    .foregroundStyle(.tujiInk)
                    .padding(.horizontal, Space.s3)
                    .padding(.vertical, Space.s1)
                    .background(self.current?.speaker == .you ? Color.tujiAccumulationSoft : .tujiBrandPrimary)
                    .overlay(Rectangle().stroke(.tujiInk, lineWidth: Border.bw1))
                    .offset(x: Space.s3, y: 1)
                    .zIndex(1)
            }
            VStack(alignment: .leading, spacing: Space.s2) {
                self.boxContent
            }
            .frame(maxWidth: .infinity, minHeight: 96, alignment: .topLeading)
            .padding(Space.s3)
            .background(.tujiPaper.opacity(0.94))
            .overlay(Rectangle().stroke(.tujiInk, lineWidth: Border.bw1))
        }
    }

    @ViewBuilder
    private var boxContent: some View {
        if let current {
            if current.speaker == .narrator {
                Text(verbatim: self.typedPart(current.text))
                    .font(.tujiBody)
                    .italic()
                    .foregroundStyle(.tujiInk2)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                HStack(alignment: .top, spacing: Space.s2) {
                    VStack(alignment: .leading, spacing: Space.s1) {
                        self.lineText(current)
                        if self.translating, let translation = current.translation, self.typed == .max {
                            Text(verbatim: translation)
                                .font(.tujiBodySm)
                                .foregroundStyle(.tujiInk2)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        ShadowingFeedback(recorder: self.recorder, line: self.shown - 1, language: self.language)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    VStack(spacing: Space.s1) {
                        PronunciationButton(
                            subject: .sentence(current.text, language: self.language),
                            size: 28,
                            ground: .tujiPaper2
                        )
                        .simultaneousGesture(TapGesture().onEnded { self.recorder.cancel() })
                        ShadowingButton(
                            recorder: self.recorder,
                            line: self.shown - 1,
                            target: current.text,
                            language: self.language
                        )
                    }
                }
            }
        } else if let story {
            Text(verbatim: self.typedPart(story.intro))
                .font(.tujiBody)
                .foregroundStyle(.tujiInk)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            self.waiting
        }
        self.footer
    }

    @ViewBuilder
    private func lineText(_ segment: Story.Segment) -> some View {
        if let furigana = segment.furigana, !furigana.isEmpty {
            FuriganaSentence(segments: furigana, font: .tujiH3)
        } else {
            Text(verbatim: self.typedPart(segment.text))
                .font(.tujiH3)
                .foregroundStyle(.tujiInk)
                .fixedSize(horizontal: false, vertical: true)
            if let reading = segment.reading, self.typed == .max {
                Text(verbatim: reading)
                    .font(.tujiBodySm)
                    .foregroundStyle(.tujiInk3)
            }
        }
    }

    /// What tells the reader a tap does something: ▼ when there is more,
    /// the writing indicator when the reader has caught up with it.
    @ViewBuilder
    private var footer: some View {
        if self.typed == .max {
            HStack {
                Spacer()
                if self.caughtUp, self.writing == .writing, self.story != nil {
                    self.waiting
                } else {
                    Image(systemName: "arrowtriangle.down.fill")
                        .font(.tujiIcon(10, weight: .bold))
                        .foregroundStyle(.tujiInk3)
                        .accessibilityHidden(true)
                }
            }
        }
    }

    // MARK: - Top bar

    private var topBar: some View {
        HStack(spacing: Space.s2) {
            if self.isIllustrated {
                Text(verbatim: self.presentation.label)
                    .font(.tujiBodySm(.strong))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .foregroundStyle(.tujiInk)
                    .padding(Space.s2)
                    .background(Color.tujiPaper.opacity(0.94))
            }
            Spacer()
            if !self.isIllustrated {
                self.chip(Text("譯"), on: self.translating) { self.translating.toggle() }
                    .accessibilityLabel(Text(self.translating ? "隱藏翻譯" : "顯示翻譯"))
            }
            self.chip(self.isIllustrated ? Text("紀錄") : Text("履歷"), on: false) {
                self.speech.stop()
                self.recorder.cancel()
                self.backlog = true
            }
        }
        .padding(Space.s3)
    }

    private func chip(_ label: Text, on: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            label
                .font(.tujiBodySm(.strong))
                .foregroundStyle(on ? Color.tujiPaper : .tujiInk)
                .padding(.horizontal, Space.s3)
                .frame(minHeight: 36)
                .background(on ? Color.tujiInk : .tujiPaper.opacity(0.92))
                .overlay(Rectangle().stroke(.tujiInk, lineWidth: Border.bw1))
                .frame(minHeight: 44)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Moving on

    private func tap() {
        guard !self.ended, !self.practicing, !self.backlog, self.story != nil else { return }
        if self.typed != .max {
            self.typing?.cancel()
            self.typed = .max
            return
        }
        if !self.caughtUp {
            let next = self.segments[self.shown]
            self.speech.stop()
            self.recorder.cancel()
            self.shown += 1
            self.typeOut()
            if next.speaker == .narrator {
                self.speech.stop()
            } else {
                self.speech.speak(next.text, voice: .preferred(for: self.settings.current, language: self.language))
            }
        } else if self.finished {
            self.speech.stop()
            self.recorder.cancel()
            withAnimation(Motion.ease(Motion.d2, reduceMotion: self.reduceMotion)) { self.ended = true }
        }
    }

    /// The text now in the box, for typing out; nil when it appears whole.
    private var typeable: String? {
        if let current {
            if current.furigana?.isEmpty == false { return nil }
            return current.text
        }
        return self.story?.intro
    }

    // MARK: - Ending

    private func ending(maxHeight: CGFloat) -> some View {
        StoryEndingPanel(story: self.story, picked: self.picked, writing: self.writing, maxHeight: maxHeight) {
            self.ended = false
            self.shown = 0
            self.typeOut()
        } close: {
            self.close()
        }
    }

    // MARK: - 履歷

    private var backlogSheet: some View {
        StoryTranscriptSheet(story: self.story, shown: self.shown, isIllustrated: self.isIllustrated) {
            self.backlog = false
        }
    }
}

private extension StoryStageView {
    func prepareStage() {
        #if DEBUG
        let args = ProcessInfo.processInfo.arguments
        if args.contains("-StoryStageDemo"), let index = args.firstIndex(of: "-StoryStageLine"),
           args.indices.contains(index + 1), let line = Int(args[index + 1])
        {
            self.shown = min(max(0, line), self.segments.count)
            self.translating = args.contains("-StoryStageTranslation")
        }
        if args.contains("-StoryStageDemo"), args.contains("-StoryStageEnding") {
            self.shown = self.segments.count
            self.ended = true
        }
        #endif
        self.typeOut()
    }

    func stopPractice() {
        self.speech.stop()
        self.recorder.cancel()
    }

    var waiting: some View {
        HStack(spacing: Space.s2) {
            TujiProgressBar(progress: nil).frame(width: 32)
            Text("Moira 正在寫故事…")
                .font(.tujiBodySm)
                .foregroundStyle(.tujiInk3)
        }
    }

    func typeOut() {
        self.typing?.cancel()
        guard !self.reduceMotion, let text = self.typeable, !text.isEmpty else {
            self.typed = .max
            return
        }
        self.typed = 0
        let count = text.count
        self.typing = Task { @MainActor in
            while self.typed < count {
                try? await Task.sleep(for: .milliseconds(32))
                if Task.isCancelled { return }
                self.typed += 1
            }
            self.typed = .max
        }
    }

    func typedPart(_ text: String) -> String {
        self.typed == .max ? text : String(text.prefix(self.typed))
    }
}
