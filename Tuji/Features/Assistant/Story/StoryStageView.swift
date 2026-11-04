// 情境故事 — read as a stage (prototype). The place fills the screen, Moira
// stands in it, and one segment at a time sits in a box along the bottom:
// a name plate for whoever speaks, nothing for narration. Tapping anywhere
// moves on; tapping while a line is still typing finishes it first.
//
// The opening — title and intro — is the first thing in the box. A spoken
// line is read aloud as it comes in, keeps its speaker and 跟讀 buttons in the
// box, and shows its translation only while 譯 is on, so the box stays small
// enough to leave Moira in view. Japanese with kana over it appears whole
// (a furigana sentence cannot be typed out unit by unit without the ruby
// jumping); everything else types out unless motion is reduced.
//
// 履歷 lists every segment already shown. When the reader catches up with a
// story still being written the box says so; after the last one, the picked
// words and the way out take the box's place.
//
// The person is never drawn: 你 is the camera. Moira's pose follows who is
// talking: waving on her lines, thinking on yours, cheering at the end.

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

    var body: some View {
        GeometryReader { geo in
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
                        self.ending
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
        .clipped()
        .sheet(isPresented: self.$backlog) { self.backlogSheet }
        .onAppear { self.typeOut() }
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

    private var waiting: some View {
        HStack(spacing: Space.s2) {
            TujiProgressBar(progress: nil).frame(width: 32)
            Text("Moira 正在寫故事…")
                .font(.tujiBodySm)
                .foregroundStyle(.tujiInk3)
        }
    }

    // MARK: - Top bar

    private var topBar: some View {
        HStack(spacing: Space.s2) {
            Spacer()
            self.chip(Text("譯"), on: self.translating) { self.translating.toggle() }
                .accessibilityLabel(Text(self.translating ? "隱藏翻譯" : "顯示翻譯"))
            self.chip(Text("履歷"), on: false) {
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
        guard !self.ended, self.story != nil else { return }
        if self.typed != .max {
            self.typing?.cancel()
            self.typed = .max
            return
        }
        if !self.caughtUp {
            let next = self.segments[self.shown]
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

    private func typeOut() {
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

    private func typedPart(_ text: String) -> String {
        self.typed == .max ? text : String(text.prefix(self.typed))
    }

    // MARK: - Ending

    private var ending: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            if case let .failed(failure) = self.writing {
                Text(verbatim: StoryBuilderView.sentence(for: failure))
                    .font(.tujiBodySm)
                    .foregroundStyle(.tujiInk3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text("故事裡的單字")
                .font(.tujiLabel)
                .tracking(0.5)
                .foregroundStyle(.tujiInk3)
            ForEach(self.picked) { word in
                NavigationLink(value: NavRoute.wordDetail(id: word.id)) {
                    HStack(spacing: Space.s3) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(verbatim: word.word)
                                .font(.tujiBody(.strong))
                                .foregroundStyle(.tujiInk)
                            Text(verbatim: self.story?.wordNotes?.first { $0.id == word.id }?.note ?? word.chinese)
                                .font(.tujiBodySm)
                                .foregroundStyle(.tujiInk3)
                        }
                        Spacer(minLength: Space.s2)
                        TujiRowAccessory()
                    }
                    .frame(minHeight: 48)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
            }
            HStack(spacing: Space.s2) {
                BBtn(title: "再看一次", bg: .tujiPaper2, fullWidth: true) {
                    self.ended = false
                    self.shown = 0
                    self.typeOut()
                }
                BBtn(title: "換個情境", fullWidth: true, action: self.close)
            }
            .padding(.top, Space.s1)
        }
        .padding(Space.s3)
        .background(.tujiPaper.opacity(0.96))
        .overlay(Rectangle().stroke(.tujiInk, lineWidth: Border.bw1))
        .transition(.opacity.combined(with: .move(edge: .bottom)))
    }

    // MARK: - 履歷

    private var backlogSheet: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Space.s3) {
                    if let story {
                        Text(verbatim: story.title).font(.tujiH3).foregroundStyle(.tujiInk)
                        Text(verbatim: story.intro).font(.tujiBodySm).foregroundStyle(.tujiInk2)
                    }
                    ForEach(Array(self.segments.prefix(self.shown).enumerated()), id: \.offset) { _, segment in
                        VStack(alignment: .leading, spacing: 2) {
                            switch segment.speaker {
                            case .narrator:
                                Text(verbatim: segment.text).font(.tujiBodySm).italic().foregroundStyle(.tujiInk3)
                            case .cat, .you:
                                Text(verbatim: segment.speaker == .cat ? "Moira" : tujiLocalized("你"))
                                    .font(.tujiLabel)
                                    .foregroundStyle(.tujiInk3)
                                Text(verbatim: segment.text).font(.tujiBody(.strong)).foregroundStyle(.tujiInk)
                                if let translation = segment.translation {
                                    Text(verbatim: translation).font(.tujiBodySm).foregroundStyle(.tujiInk2)
                                }
                            }
                        }
                        .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(Space.s4)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(Color.tujiPaper)
            .navigationTitle(Text("履歷"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("關閉") { self.backlog = false }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

#if DEBUG
/// A finished story at a chosen place, for looking at the stage without
/// spending points. Launch with `-StoryStageDemo <sceneId>`.
struct StoryStageDemo: View {
    let sceneId: String

    static var requestedScene: String? {
        let args = ProcessInfo.processInfo.arguments
        guard let index = args.firstIndex(of: "-StoryStageDemo") else { return nil }
        return args.indices.contains(index + 1) ? args[index + 1] : "supermarket"
    }

    var body: some View {
        NavigationStack {
            StoryStageView(
                story: Self.story,
                sceneId: self.sceneId,
                language: .ja,
                picked: [],
                writing: .idle,
                close: {}
            )
        }
    }

    private typealias Ruby = [(String, String?)]
    private typealias Who = Story.Segment.Speaker

    private static func line(_ speaker: Who, _ text: String, _ ruby: Ruby?, _ tr: String?) -> Story.Segment {
        Story.Segment(
            speaker: speaker,
            text: text,
            furigana: ruby?.map { FuriganaSegment(text: $0.0, ruby: $0.1) },
            reading: nil,
            translation: tr,
            wordIds: []
        )
    }

    private static let tasty: Ruby = [("この", nil), ("りんご", nil), ("、", nil), ("美味", "おい"), ("しそうですね。", nil)]
    private static let howMany: Ruby = [("いくつ", nil), ("買", "か"), ("いますか。", nil)]
    private static let three: Ruby = [("三", "みっ"), ("つ", nil), ("買", "か"), ("いましょう。", nil)]

    // Sample story content, not interface copy: kept out of the `title:` call
    // so the localisation check does not read it as a key.
    private static let sampleTitle = "和Moira一起買蘋果"
    private static let sampleIntro = "你和Moira走進超市，在水果區看到一籃紅色的蘋果。你想買一些回家，Moira陪你一起挑選。"

    static let story = Story(
        title: sampleTitle,
        intro: sampleIntro,
        segments: [
            line(.cat, "このりんご、美味しそうですね。", tasty, "這個蘋果看起來很好吃呢。"),
            line(.you, "いくつ買いますか。", howMany, "要買幾個？"),
            line(.narrator, "Moira 拿起一顆蘋果，仔細看了看。", nil, nil),
            line(.cat, "三つ買いましょう。", three, "買三個吧。"),
            line(.you, "はい、そうしましょう。", nil, "好，就這麼辦。")
        ],
        wordNotes: nil
    )
}
#endif
