// 圖鑑主題對話 — what opens over the conversation: the topic picker, 幫我表達,
// a word from the pictures, the review, and the list of saved conversations.

import SwiftUI

/// 更換圖鑑. The catalogue categories with enough words in the language being
/// learned to carry a conversation; the server makes the same check.
struct TopicPickerSheet: View {
    let current: String?
    let pick: (String) -> Void

    @Environment(\.dismiss) private var dismiss

    /// The server's `MIN_TOPIC_WORDS`.
    static let minimumWords = 6

    /// A catalogue theme (not 自製 or 物見) with enough words to talk about —
    /// the same rule on the category page, in this list, and on the server.
    static func canTalk(about categoryId: String, wordCount: Int) -> Bool {
        wordCount >= self.minimumWords && ThemeCatalog.isTheme(categoryId)
    }

    var body: some View {
        NavigationStack {
            TopicChoiceList(current: self.current, dismiss: { self.dismiss() }, pick: self.pick) {
                Text("換主題後，對話會接著聊，學過的說法還能繼續用。")
            }
            .navigationTitle(Text("更換圖鑑"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { self.dismiss() }
                }
            }
        }
    }
}

/// The topics, as a list: in 更換圖鑑's sheet, and on the conversation screen
/// itself when it was opened without one.
struct TopicChoiceList<Footer: View>: View {
    let current: String?
    var dismiss: () -> Void = {}
    /// Nil keeps the list's own; the conversation screen passes paper.
    var rowBackground: Color?
    let pick: (String) -> Void
    @ViewBuilder let footer: () -> Footer

    @Environment(CategoriesStore.self) private var categories
    @Environment(WordsStore.self) private var words

    private var topics: [(category: TujiCategory, count: Int)] {
        let all = self.categories.categories
        let present = Set(all.map(\.id).filter { !self.words.byCategory($0).isEmpty })
        return ThemeCatalog.themes(from: all, presentIds: present).map {
            ($0, self.words.byCategory($0.id).count)
        }
    }

    var body: some View {
        List {
            Section {
                ForEach(self.topics, id: \.category.id) { topic in
                    let usable = TopicPickerSheet.canTalk(about: topic.category.id, wordCount: topic.count)
                    Button {
                        if topic.category.id == self.current {
                            self.dismiss()
                        } else {
                            self.pick(topic.category.id)
                        }
                    } label: {
                        HStack(spacing: Space.s3) {
                            CategoryArtwork(category: topic.category)
                                .frame(width: 44, height: 44)
                                .clipped()
                            VStack(alignment: .leading, spacing: 2) {
                                Text(verbatim: topic.category.nameZh)
                                    .font(.tujiBody(.strong))
                                    .foregroundStyle(usable ? .tujiInk : .tujiInk3)
                                Text(usable ? "\(topic.count) 個詞" : "暫不可用")
                                    .font(.tujiBodySm)
                                    .foregroundStyle(.tujiInk3)
                            }
                            Spacer(minLength: Space.s2)
                            if topic.category.id == self.current {
                                Text("目前主題")
                                    .font(.tujiLabel)
                                    .foregroundStyle(.tujiInk2)
                            }
                        }
                        .frame(minHeight: 52)
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .disabled(!usable)
                    .listRowBackground(self.rowBackground)
                }
            } footer: {
                self.footer()
            }
        }
        .task {
            await self.categories.loadIfNeeded()
            await self.words.loadIfNeeded()
        }
    }
}

/// 幫我表達 — write the idea in whatever language comes easiest; the sentence
/// comes back here and reaches the draft only on 帶入回答. Nothing typed here
/// becomes a chat message.
struct ExpressPanel: View {
    @Bindable var model: TopicChatModel
    let close: () -> Void

    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Space.s4) {
                    Text("用你熟悉的語言寫下想說的話，Moira 幫你換成可以回答的句子。")
                        .font(.tujiBodySm)
                        .foregroundStyle(.tujiInk2)
                        .fixedSize(horizontal: false, vertical: true)
                    TextField("例如：我想買水", text: self.$model.express.idea, axis: .vertical)
                        .lineLimit(2...5)
                        .focused(self.$focused)
                        .font(.tujiBody)
                        .padding(Space.s3)
                        .background(.tujiPaper2)
                    if let result = self.model.express.result {
                        VStack(alignment: .leading, spacing: Space.s2) {
                            Text("可以這樣說")
                                .font(.tujiLabel)
                                .tracking(0.5)
                                .foregroundStyle(.tujiBrandSecondary)
                            ChatSentence(
                                text: result,
                                showTranslation: true,
                                showReading: self.model.showReading
                            )
                        }
                        .padding(Space.s3)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.tujiPaper2)
                        BBtn(title: "帶入回答", fullWidth: true) {
                            self.model.useExpressed()
                            self.close()
                        }
                    }
                    if let failure = self.model.express.failure {
                        Text(verbatim: TopicChatView.sentence(for: failure))
                            .font(.tujiBodySm)
                            .foregroundStyle(.tujiInk3)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if self.model.express.working {
                        TujiProgressBar(progress: nil).frame(width: 60)
                    } else {
                        BBtn(
                            title: self.model.express.result == nil ? "幫我說" : "再說一次",
                            bg: self.model.express.result == nil ? .tujiBrandPrimary : .tujiPaper2,
                            fullWidth: true
                        ) {
                            Task { await self.model.expressIdea() }
                        }
                        .disabled(self.model.express.idea.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                    Text("免費輔助還有 \(self.model.state?.assistsLeft ?? 0) 次")
                        .font(.tujiLabel)
                        .foregroundStyle(.tujiInk3)
                }
                .padding(Space.s4)
            }
            .background(Color.tujiPaper)
            .navigationTitle(Text("幫我表達"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        self.model.closeExpress()
                        self.close()
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .onAppear { self.focused = true }
    }
}

/// A topic picture, explained. 用這個回答 is the only way it reaches the draft.
struct ChatWordSheet: View {
    let word: CardWord
    let canUse: Bool
    let use: () -> Void
    let open: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            HStack(spacing: Space.s3) {
                Color.tujiPaper2
                    .frame(width: 88, height: 88)
                    .overlay { WordPicture(url: self.word.imageURL, kind: self.word.imageKind, inset: Space.s2) }
                    .clipped()
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: self.word.word)
                        .font(.tujiH2)
                        .foregroundStyle(.tujiInk)
                    if let reading = self.word.reading, reading != self.word.word {
                        Text(verbatim: reading)
                            .font(.tujiBodySm)
                            .foregroundStyle(.tujiInk3)
                    }
                    Text(verbatim: self.word.chinese)
                        .font(.tujiBody)
                        .foregroundStyle(.tujiInk2)
                }
                Spacer(minLength: 0)
            }
            if self.canUse {
                BBtn(title: "用這個回答", fullWidth: true, action: self.use)
            }
            BBtn(title: "看完整詞條", bg: .tujiPaper2, fullWidth: true, action: self.open)
        }
        .padding(Space.s4)
        .presentationDetents([.height(self.canUse ? 300 : 240)])
        .background(Color.tujiPaper)
    }
}

/// 回顧 — at the end of an ended conversation. Only what was said: the person's
/// own sentences apart from Moira's, and a suggestion marked as one.
struct ChatReviewSection: View {
    let chat: TopicChatSummary
    let failed: Bool
    let showTranslation: Bool
    let showReading: Bool
    let retry: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            Text("這段對話已結束")
                .font(.tujiLabel)
                .tracking(0.5)
                .foregroundStyle(.tujiInk3)
            if let review = self.chat.review {
                Text("回顧")
                    .font(.tujiH3)
                    .foregroundStyle(.tujiInk)
                Text("聊過：\(review.topics.map(\.name).joined(separator: "、"))")
                    .font(.tujiBodySm)
                    .foregroundStyle(.tujiInk2)
                self.phrases(review.phrases.filter { $0.source == "you" }, title: "你說過的")
                self.phrases(review.phrases.filter { $0.source == "moira" }, title: "Moira 示範過的")
                if let tryNext = review.tryNext {
                    VStack(alignment: .leading, spacing: Space.s1) {
                        Text("下次可以試")
                            .font(.tujiLabel)
                            .foregroundStyle(.tujiBrandSecondary)
                        ChatSentence(
                            text: tryNext,
                            showTranslation: self.showTranslation,
                            showReading: self.showReading
                        )
                    }
                }
                if !review.nextIdea.isEmpty {
                    Text(verbatim: review.nextIdea)
                        .font(.tujiBody)
                        .foregroundStyle(.tujiInk2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else if self.failed {
                Text("回顧沒有整理好。對話都還在，可以再試一次。")
                    .font(.tujiBodySm)
                    .foregroundStyle(.tujiInk2)
                Button("重新整理回顧", action: self.retry)
                    .buttonStyle(.plain)
                    .font(.tujiBodySm(.strong))
                    .foregroundStyle(.tujiInk)
                    .frame(minHeight: 44)
            } else if self.chat.answers == 0 {
                Text("這段對話還沒有回答，所以沒有回顧。")
                    .font(.tujiBodySm)
                    .foregroundStyle(.tujiInk2)
            } else {
                Button("整理回顧", action: self.retry)
                    .buttonStyle(.plain)
                    .font(.tujiBodySm(.strong))
                    .foregroundStyle(.tujiInk)
                    .frame(minHeight: 44)
            }
        }
        .padding(Space.s3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.tujiPaper2)
    }

    @ViewBuilder
    private func phrases(_ phrases: [ChatReview.Phrase], title: LocalizedStringKey) -> some View {
        if !phrases.isEmpty {
            VStack(alignment: .leading, spacing: Space.s2) {
                Text(title)
                    .font(.tujiLabel)
                    .foregroundStyle(.tujiInk3)
                ForEach(Array(phrases.enumerated()), id: \.offset) { _, phrase in
                    ChatSentence(
                        text: phrase.text,
                        showTranslation: self.showTranslation,
                        showReading: self.showReading
                    )
                }
            }
        }
    }
}

/// 對話紀錄 — saved conversations in the language being learned. Ended ones
/// are for reading; deleting one deletes its review and anything still being written.
struct TopicChatHistoryView: View {
    @State private var model = TopicChatModel(entry: .saved(chatId: ""))

    var body: some View {
        VStack(spacing: 0) {
            TujiNavBar(leading: .back, compactTitle: Text("對話紀錄"), showsRule: true) {}
            List {
                if self.model.history.isEmpty {
                    Text("還沒有保存的對話。")
                        .font(.tujiBodySm)
                        .foregroundStyle(.tujiInk3)
                        .listRowBackground(Color.tujiPaper)
                }
                ForEach(self.model.history) { chat in
                    NavigationLink(value: NavRoute.topicChat(.saved(chatId: chat.id))) {
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: Space.s2) {
                                Text(verbatim: chat.topicName)
                                    .font(.tujiBody(.strong))
                                    .foregroundStyle(.tujiInk)
                                if chat.isActive {
                                    Text("進行中")
                                        .font(.tujiLabel)
                                        .foregroundStyle(.tujiBrandSecondary)
                                }
                            }
                            Text("回答 \(chat.answers) 次")
                                .font(.tujiBodySm)
                                .foregroundStyle(.tujiInk3)
                        }
                        .frame(minHeight: 52, alignment: .leading)
                    }
                    .listRowBackground(Color.tujiPaper)
                    .swipeActions {
                        Button(role: .destructive) {
                            Task { _ = await self.model.delete(chatId: chat.id) }
                        } label: {
                            Label("刪除", systemImage: "trash")
                        }
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .refreshable { await self.model.loadHistory() }
        }
        .background(Color.tujiPaper.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .task { await self.model.loadHistory() }
    }
}
