import SwiftUI

/// Keeps the illustration above the *measured* dialogue, including translation.
struct StoryStageLayout<Panel: View>: View {
    let presentation: StoryStagePresentation
    let reduceMotion: Bool
    let advance: () -> Void
    let panel: Panel
    @State private var panelHeight: CGFloat = 180

    init(
        presentation: StoryStagePresentation,
        reduceMotion: Bool,
        advance: @escaping () -> Void,
        @ViewBuilder panel: () -> Panel
    ) {
        self.presentation = presentation
        self.reduceMotion = reduceMotion
        self.advance = advance
        self.panel = panel()
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .bottom) {
                Image(self.presentation.backgroundImageName)
                    .resizable()
                    .scaledToFill()
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .clipped()
                    .id(self.presentation.backgroundImageName)
                    .transition(.opacity)
                    .accessibilityHidden(true)
                StoryStageMoira(
                    action: self.presentation.action,
                    size: CGSize(
                        width: geometry.size.width,
                        height: max(0, geometry.size.height - self.panelHeight - Space.s4)
                    )
                )
                .frame(maxHeight: .infinity, alignment: .top)
                .allowsHitTesting(false)
                Color.clear
                    .contentShape(.rect)
                    .onTapGesture(perform: self.advance)
                    .accessibilityHidden(true)
                self.panel
                    .onGeometryChange(for: CGFloat.self, of: \.size.height) { self.panelHeight = $0 }
                    .padding(.horizontal, Space.s3)
                    .padding(.bottom, Space.s3)
            }
            .animation(self.reduceMotion ? nil : .easeInOut(duration: 0.2), value: self.presentation)
        }
        .clipped()
    }
}

private struct StoryStageMoira: View {
    let action: StoryStagePresentation.Action
    let size: CGSize

    var body: some View {
        let bounds = StorySpriteMetrics.bounds(for: self.action)
        let visibleHeight = min(max(0, self.size.height - 96), self.size.width * 0.80)
        let canvas = visibleHeight / (bounds.bottom - bounds.top)
        let ground = self.size.height - Space.s2
        let left = Space.s3 - bounds.left * canvas
        ZStack(alignment: .topLeading) {
            Ellipse()
                .fill(Color.tujiInk.opacity(0.16))
                .frame(width: canvas * (bounds.right - bounds.left) * 0.7, height: 12)
                .blur(radius: 5)
                .position(x: left + (bounds.left + bounds.right) * canvas / 2, y: ground)
            Image(self.action.imageName)
                .resizable()
                .scaledToFit()
                .frame(width: canvas, height: canvas)
                .position(x: left + canvas / 2, y: ground - bounds.bottom * canvas + canvas / 2)
                .id(self.action)
                .transition(.opacity)
        }
        .frame(width: self.size.width, height: self.size.height)
        .accessibilityHidden(true)
    }
}

struct StoryDialogue<Content: View, Controls: View>: View {
    let name: String?
    let isReader: Bool
    let maxHeight: CGFloat
    let contentKey: Int
    @ViewBuilder let content: () -> Content
    @ViewBuilder let controls: () -> Controls
    @State private var contentHeight: CGFloat = 72
    @State private var contentWidth: CGFloat = 280
    @State private var nameHeight: CGFloat = 28
    @State private var controlsHeight: CGFloat = 88

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let name {
                Text(verbatim: name)
                    .font(.tujiBodySm(.strong))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .foregroundStyle(.tujiInk)
                    .padding(.horizontal, Space.s3)
                    .padding(.vertical, Space.s1)
                    .background(self.isReader ? Color.tujiAccumulationSoft : .tujiBrandPrimary)
                    .overlay(Rectangle().stroke(.tujiInk, lineWidth: Border.bw1))
                    .offset(x: Space.s3, y: 1)
                    .zIndex(1)
                    .onGeometryChange(for: CGFloat.self, of: \.size.height) { self.nameHeight = $0 }
                    .padding(.trailing, Space.s3)
            }
            VStack(alignment: .leading, spacing: Space.s2) {
                ScrollViewReader { proxy in
                    ScrollView {
                        self.content()
                            // FlowLayout must measure with the same finite width it
                            // will place in; otherwise wrapped ruby can overflow a
                            // one-line scroll content size at accessibility sizes.
                            .frame(width: self.contentWidth, alignment: .leading)
                            .fixedSize(horizontal: false, vertical: true)
                            .onGeometryChange(for: CGFloat.self, of: \.size.height) { self.contentHeight = $0 }
                        Color.clear.frame(height: 1).id("story-dialogue-end")
                    }
                    .onGeometryChange(for: CGFloat.self, of: \.size.width) { self.contentWidth = $0 }
                    .frame(height: min(
                        self.contentHeight,
                        max(
                            1,
                            self.maxHeight - (self.name == nil ? 0 : self.nameHeight) - self.controlsHeight - Space
                                .s3 * 2 - Space.s2
                        )
                    ))
                    .onChange(of: self.contentHeight) {
                        #if DEBUG
                        if ProcessInfo.processInfo.arguments.contains("-StoryStageScrollToEnd") {
                            proxy.scrollTo("story-dialogue-end", anchor: .bottom)
                        }
                        #endif
                    }
                }
                .id(self.contentKey)
                self.controls()
                    .onGeometryChange(for: CGFloat.self, of: \.size.height) { self.controlsHeight = $0 }
            }
            .padding(Space.s3)
            .background(Color.tujiPaper)
            .overlay(Rectangle().stroke(.tujiInk, lineWidth: Border.bw1))
        }
    }
}

struct StoryPracticeSheet: View {
    let segment: Story.Segment
    let line: Int
    let language: TargetLanguage
    let recorder: ShadowingRecorder
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Space.s4) {
                    if let ruby = self.segment.furigana, !ruby.isEmpty {
                        FuriganaSentence(segments: ruby, font: .tujiH3)
                    } else {
                        Text(verbatim: self.segment.text).font(.tujiH3)
                    }
                    ShadowingButton(
                        recorder: self.recorder, line: self.line, target: self.segment.text,
                        language: self.language, size: 48
                    )
                    ShadowingFeedback(recorder: self.recorder, line: self.line, language: self.language)
                }
                .padding(Space.s4)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(Color.tujiPaper)
            .foregroundStyle(.tujiInk)
            .navigationTitle(Text("跟讀"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("關閉") { self.dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .onDisappear { self.recorder.cancel() }
    }
}
