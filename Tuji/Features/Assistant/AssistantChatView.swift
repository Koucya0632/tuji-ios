// 助手 — the conversation, reached from the assistant home.
//
// The model is `AssistantChatModel`; what an answer contains is decided behind
// `AssistantResponding`. This file only draws.
//
// The cat's words sit directly on the paper, beside its face, rather than in a
// bubble: `MascotSpeechBubble` is a pill, and a pill holds one short line. An
// answer here runs to a sentence and a list. What the user said is the block —
// a square of `tujiPaper2`, the same hole-in-the-paper the search field is.

import SwiftUI

struct AssistantChatView: View {
    @Environment(StudyFocus.self) private var studyFocus
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var model: AssistantChatModel
    @State private var draft = ""
    @FocusState private var fieldFocused: Bool
    private let entry: AssistantChatEntry

    /// The model is a parameter so a preview or a later tier can hand in one
    /// built over a different responder.
    init(model: AssistantChatModel = AssistantChatModel(), entry: AssistantChatEntry = .conversation) {
        _model = State(initialValue: model)
        self.entry = entry
    }

    var body: some View {
        VStack(spacing: 0) {
            TujiNavBar(leading: .back, compactTitle: Text("助手"), showsRule: true) {
                AssistantCreditLink()
            }
            self.conversation
            self.composer
        }
        .background(Color.tujiPaper.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        // The same flag 搜尋 uses: the custom tab bar would otherwise sit on top
        // of the input field.
        .onAppear {
            self.studyFocus.enter()
            if self.model.start(self.entry) {
                self.fieldFocused = self.entry.focusesComposer
            }
        }
        .onDisappear { self.studyFocus.exit() }
    }

    // MARK: - 對話

    private var conversation: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: Space.s4) {
                    ForEach(self.model.messages) { message in
                        Group {
                            switch message.body {
                            case let .user(text): self.userRow(text)
                            case let .mascot(reply): AssistantReplyRow(reply: reply)
                            }
                        }
                        .id(message.id)
                    }
                    if self.model.replying {
                        TujiProgressBar(progress: nil)
                            .frame(width: 40)
                            .padding(.leading, AssistantReplyRow.textInset)
                    }
                    self.chips
                }
                .padding(.horizontal, Space.s4)
                .padding(.vertical, Space.s4)
            }
            .scrollDismissesKeyboard(.interactively)
            // To the top of the newest message, not the bottom of the list: an
            // answer can be a sentence and twenty rows, and landing on the last
            // row hides the sentence that says what the rows are. A short
            // answer cannot over-scroll, so it still ends up at the bottom.
            .onChange(of: self.model.messages.last?.id) { _, newest in
                guard let newest else { return }
                withAnimation(self.reduceMotion ? nil : Motion.ease(Motion.d2)) {
                    proxy.scrollTo(newest, anchor: .top)
                }
            }
        }
    }

    private func userRow(_ text: String) -> some View {
        Text(verbatim: text)
            .font(.tujiBody)
            .foregroundStyle(.tujiInk)
            .padding(.horizontal, Space.s3)
            .padding(.vertical, Space.s2)
            .background(.tujiPaper2)
            .frame(maxWidth: .infinity, alignment: .trailing)
            .padding(.leading, Space.s5)
    }

    /// Whatever the cat last offered. Under the conversation rather than inside
    /// the message, so an old answer's choices do not stay tappable above a
    /// newer one.
    @ViewBuilder
    private var chips: some View {
        let suggestions = self.model.suggestions
        if !suggestions.isEmpty, !self.model.replying {
            FlowLayout(spacing: Space.s2) {
                ForEach(suggestions, id: \.self) { intent in
                    Button {
                        self.model.choose(intent)
                    } label: {
                        Text(verbatim: intent.chipTitle)
                            .font(.tujiBodySm(.strong))
                            .foregroundStyle(.tujiInk)
                            .padding(.horizontal, Space.s3)
                            .frame(minHeight: 44)
                            // A ground, not an outline: a resting element
                            // with a border is a bug (Border.swift).
                            .background(.tujiPaper2)
                            .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.leading, AssistantReplyRow.textInset)
        }
    }

    // MARK: - 輸入

    private var composer: some View {
        VStack(spacing: Space.s2) {
            self.storyEntry
            HStack(spacing: Space.s2) {
                TextField("問我分類、收藏，或打一個字", text: self.$draft)
                    .focused(self.$fieldFocused)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.send)
                    .onSubmit(self.submit)
                    .font(.tujiBody)
                    .foregroundStyle(.tujiInk)
                    .tint(.tujiInk)
                    .padding(.horizontal, Space.s3)
                    .frame(height: 52)
                    .background(.tujiPaper2)
                    .overlay {
                        if self.fieldFocused {
                            Rectangle().stroke(.tujiCurrent, lineWidth: Border.bw2)
                        }
                    }
                    .animation(Motion.ease(Motion.d1), value: self.fieldFocused)

                Button(action: self.submit) {
                    Image(systemName: "arrow.up")
                        .font(.tujiIcon(17, weight: .bold))
                        .foregroundStyle(self.canSend ? Color.tujiPaper : .tujiInk3)
                        .frame(width: 52, height: 52)
                        .background(self.canSend ? Color.tujiInk : .tujiPaper2)
                }
                .buttonStyle(.plain)
                .disabled(!self.canSend)
                .accessibilityLabel(Text("送出"))
            }

            // It sits behind a chat field and part of it costs points, so it
            // owes the user the sentence that says which part.
            Text("查圖鑑裡的詞不用點數；問 AI 才會扣罐頭點數。")
                .font(.tujiLabel)
                .foregroundStyle(.tujiInk3)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, Space.s4)
        .padding(.vertical, Space.s2)
        .background(alignment: .top) {
            Rectangle().fill(.tujiRule).frame(height: Border.bw1)
        }
    }

    /// 情境故事 — the other thing 助手 does. Above the field rather than among
    /// the chips: the chips are answers to what was just said, and this is
    /// always there.
    private var storyEntry: some View {
        NavigationLink(value: NavRoute.assistantStory) {
            HStack(spacing: Space.s2) {
                Text("情境故事")
                    .font(.tujiBodySm(.strong))
                    .foregroundStyle(.tujiInk)
                Text("選幾個單字，開始一段對話")
                    .font(.tujiBodySm)
                    .foregroundStyle(.tujiInk3)
                    .lineLimit(1)
                Spacer(minLength: Space.s2)
                TujiRowAccessory()
            }
            .padding(.horizontal, Space.s3)
            .frame(minHeight: 44)
            .background(.tujiPaper2)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }

    private var canSend: Bool {
        !self.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func submit() {
        guard self.canSend else { return }
        self.model.send(self.draft)
        self.draft = ""
    }
}

// MARK: - 一則回覆

private struct AssistantReplyRow: View {
    let reply: AssistantReply

    private static let faceSize: CGFloat = 36
    /// Where the cat's words start, so chips and the progress bar line up
    /// under them rather than under its face.
    static let textInset: CGFloat = faceSize + Space.s2

    var body: some View {
        HStack(alignment: .top, spacing: Space.s2) {
            Mascot(pose: .face, size: Self.faceSize)
            VStack(alignment: .leading, spacing: Space.s3) {
                Text(verbatim: self.reply.text)
                    .font(.tujiBody)
                    .foregroundStyle(.tujiInk)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(minHeight: Self.faceSize, alignment: .leading)
                if let attachment = self.reply.attachment {
                    self.attached(attachment)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private func attached(_ attachment: AssistantReply.Attachment) -> some View {
        switch attachment {
        case let .words(words, total, more):
            self.rows(words) { word in
                NavigationLink(value: NavRoute.wordDetail(id: word.id)) {
                    AssistantRow(title: word.word, subtitle: word.chinese) {
                        WordPicture(
                            url: word.imageURL,
                            kind: word.imageKind,
                            inset: Space.s1,
                            glyphSize: 14
                        )
                    }
                }
            }
            if let more {
                NavigationLink(value: more) {
                    HStack(spacing: Space.s2) {
                        Text("看全部 \(total) 筆")
                            .font(.tujiBodySm(.strong))
                        Image(systemName: "arrow.right")
                            .font(.tujiIcon(14, weight: .semibold))
                    }
                    .foregroundStyle(.tujiInk)
                    .frame(minHeight: 44)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func rows<Item: Identifiable>(
        _ items: [Item],
        @ViewBuilder row: @escaping (Item) -> some View
    )
        -> some View
    {
        VStack(spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                if index > 0 {
                    Rectangle().fill(.tujiRule).frame(height: Border.bw1)
                }
                row(item).tujiRowStyle()
            }
        }
        .overlay(alignment: .top) { Rectangle().fill(.tujiRule).frame(height: Border.bw1) }
        .overlay(alignment: .bottom) { Rectangle().fill(.tujiRule).frame(height: Border.bw1) }
    }
}

/// One thing the cat found: a picture, a name, a line under it, and the arrow
/// that says it goes somewhere.
private struct AssistantRow<Thumb: View>: View {
    static var thumbSize: CGFloat {
        44
    }

    let title: String
    let subtitle: String?
    @ViewBuilder var thumb: Thumb

    var body: some View {
        HStack(spacing: Space.s3) {
            // The container owns the square; the picture fills it (a portrait
            // cut-out must not make its own row taller than its neighbours').
            Color.tujiPaper2
                .frame(width: Self.thumbSize, height: Self.thumbSize)
                .overlay { self.thumb }
                .clipped()
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: self.title)
                    .font(.tujiBody(.strong))
                    .foregroundStyle(.tujiInk)
                    .lineLimit(1)
                if let subtitle, !subtitle.isEmpty {
                    Text(verbatim: subtitle)
                        .font(.tujiBodySm)
                        .foregroundStyle(.tujiInk3)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: Space.s2)
            TujiRowAccessory()
        }
        .frame(minHeight: 64)
        .contentShape(.rect)
    }
}

#Preview {
    NavigationStack {
        AssistantChatView()
            .environment(StudyFocus.shared)
            .environment(SettingsStore.shared)
    }
}
