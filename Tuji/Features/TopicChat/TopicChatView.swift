// 圖鑑主題對話 — the screen. `TopicChatModel` holds the state; this draws it.
//
// Top: the topic (tap to change it) and a menu for the reading supports and
// ending. Middle: the conversation, where only the newest turn offers answer
// actions. Bottom: the draft, 送出／停止, and 幫我接話 — one entry that opens
// the five supports rather than five buttons beside the field.

import SwiftUI

struct TopicChatView: View {
    @Environment(StudyFocus.self) private var studyFocus
    @Environment(TabNavigator.self) private var navigator
    @Environment(WordsStore.self) private var words
    @Environment(CategoriesStore.self) private var categories
    @Environment(\.presentPaywall) private var presentPaywall
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dismiss) private var dismiss

    @State private var model: TopicChatModel
    @State private var picking = false
    @State private var supportsOpen = false
    @State private var expressing = false
    @State private var confirmingDelete = false
    @State private var lookedUp: CardWord?
    @FocusState private var fieldFocused: Bool

    init(entry: TopicChatEntry) {
        _model = State(initialValue: TopicChatModel(entry: entry))
    }

    init(model: TopicChatModel) {
        _model = State(initialValue: model)
    }

    var body: some View {
        VStack(spacing: 0) {
            self.navBar
            self.content
        }
        .background(Color.tujiPaper.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .onAppear { self.studyFocus.enter() }
        .onDisappear {
            self.studyFocus.exit()
            self.model.leave()
        }
        .task {
            await self.categories.loadIfNeeded()
            await self.words.loadIfNeeded()
            await self.model.load()
        }
        .sheet(isPresented: self.$picking) {
            TopicPickerSheet(current: self.model.chat?.topicId) { topicId in
                self.picking = false
                Task { await self.model.switchTopic(to: topicId) }
            }
        }
        .sheet(isPresented: self.$expressing) {
            ExpressPanel(model: self.model) {
                self.expressing = false
            }
        }
        .sheet(item: self.$lookedUp) { word in
            ChatWordSheet(word: word, canUse: self.model.isActive && self.model.latestTurn != nil) {
                self.lookedUp = nil
                self.model.fill(word.word, support: .hint)
            } open: {
                self.lookedUp = nil
                self.navigator.push(.wordDetail(id: word.id))
            }
        }
        .confirmationDialog(
            Text("草稿裡已經有內容"),
            isPresented: Binding(
                get: { self.model.pendingFill != nil },
                set: { if !$0 { self.model.resolveFill(.cancel) } }
            ),
            titleVisibility: .visible
        ) {
            Button("替換草稿") { self.model.resolveFill(.replace) }
            Button("加在後面") { self.model.resolveFill(.append) }
            Button("取消", role: .cancel) { self.model.resolveFill(.cancel) }
        }
        .tujiPrompt(
            isPresented: self.$confirmingDelete,
            style: .destructive,
            title: "刪除這段對話？",
            message: "對話、回顧和還在生成的內容都會一起刪除，無法復原。",
            primary: TujiPromptAction("刪除", role: .destructive) {
                guard let id = self.model.chat?.id else { return }
                Task {
                    if await self.model.delete(chatId: id) { self.dismiss() }
                }
            },
            secondary: TujiPromptAction("取消", role: .cancel) {}
        )
    }

    // MARK: - 頂部

    private var navBar: some View {
        TujiNavBar(leading: .back, showsRule: true) {
            HStack(spacing: Space.s2) {
                if let chat = self.model.chat {
                    self.topicButton(chat)
                }
                self.menu
            }
        }
    }

    private func topicButton(_ chat: TopicChatSummary) -> some View {
        Button {
            self.picking = true
        } label: {
            HStack(spacing: Space.s2) {
                if let category = self.categories.find(id: chat.topicId) {
                    CategoryArtwork(category: category)
                        .frame(width: 28, height: 28)
                        .clipped()
                }
                VStack(alignment: .leading, spacing: 0) {
                    Text("目前主題")
                        .font(.tujiLabel)
                        .foregroundStyle(.tujiInk3)
                    Text(verbatim: chat.topicName)
                        .font(.tujiBodySm(.strong))
                        .foregroundStyle(.tujiInk)
                        .lineLimit(1)
                }
                if self.model.isActive {
                    Text("更換圖鑑")
                        .font(.tujiLabel)
                        .foregroundStyle(.tujiInk2)
                        .padding(.horizontal, Space.s2)
                        .frame(minHeight: 28)
                        .background(.tujiPaper2)
                }
            }
            .frame(minHeight: 44)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(!self.model.isActive)
        .accessibilityElement(children: .combine)
        .accessibilityHint(Text("更換圖鑑"))
    }

    private var menu: some View {
        Menu {
            Toggle("顯示翻譯", isOn: self.$model.showTranslation)
            if self.isJapanese {
                Toggle("顯示讀音", isOn: self.$model.showReading)
            }
            Divider()
            NavigationLink(value: NavRoute.topicChatHistory) {
                Label("對話紀錄", systemImage: "clock")
            }
            if self.model.isActive {
                Button {
                    Task { await self.model.end(review: true) }
                } label: {
                    Label("結束並回顧", systemImage: "checkmark.circle")
                }
                .disabled((self.model.chat?.answers ?? 0) == 0)
                Button {
                    Task { await self.model.end(review: false) }
                } label: {
                    Label("結束", systemImage: "xmark.circle")
                }
            } else if self.model.chat != nil {
                Button(role: .destructive) {
                    self.confirmingDelete = true
                } label: {
                    Label("刪除這段對話", systemImage: "trash")
                }
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.tujiIcon(17, weight: .bold))
                .foregroundStyle(.tujiInk)
                .frame(width: 44, height: 44)
                .contentShape(.rect)
        }
        .accessibilityLabel(Text("對話選單"))
    }

    private var isJapanese: Bool {
        (self.model.chat?.learningDirection ?? SettingsStore.shared.current.learningDirection.rawValue) == "zh-ja"
    }

    private var targetLanguage: TargetLanguage {
        self.isJapanese ? .ja : .en
    }

    // MARK: - 狀態

    @ViewBuilder
    private var content: some View {
        switch self.model.phase {
        case .idle, .loading:
            VStack(spacing: Space.s3) {
                TujiProgressBar(progress: nil).frame(width: 60)
                Text("Moira 正在準備話題…")
                    .font(.tujiBodySm)
                    .foregroundStyle(.tujiInk3)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case let .choosing(active):
            self.resumeChoice(active)
        case .picking:
            self.topicChoice
        case let .failed(failure):
            self.failedState(failure)
        case .ready:
            VStack(spacing: 0) {
                self.conversation
                if self.model.isActive {
                    self.composer
                } else {
                    self.endedFooter
                }
            }
        }
    }

    private var entryTopicId: String? {
        if case let .topic(id) = self.model.entry { return id }
        return nil
    }

    private func topicName(_ id: String) -> String {
        self.categories.find(id: id)?.nameZh ?? id
    }

    private func resumeChoice(_ active: TopicChatSummary) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.s4) {
                Mascot(pose: .wave, size: 72)
                Text("上次的對話還在")
                    .font(.tujiH2)
                    .foregroundStyle(.tujiInk)
                Text("上次主題：\(active.topicName)")
                    .font(.tujiBody)
                    .foregroundStyle(.tujiInk2)
                BBtn(title: "繼續上次", fullWidth: true) {
                    Task { await self.model.continueActive() }
                }
                if let topic = self.entryTopicId {
                    BBtn(
                        localized: tujiLocalized("用「\(self.topicName(topic))」開始新對話"),
                        bg: .tujiPaper2,
                        fullWidth: true
                    ) {
                        Task { await self.model.startNew(topicId: topic) }
                    }
                    Text("開始新對話後，上次的對話會結束，仍可在對話紀錄裡閱讀。")
                        .font(.tujiBodySm)
                        .foregroundStyle(.tujiInk3)
                        .fixedSize(horizontal: false, vertical: true)
                } else if self.model.entry == .choose {
                    BBtn(title: "換個主題開始新對話", bg: .tujiPaper2, fullWidth: true) {
                        self.model.pickNewTopic()
                    }
                    Text("開始新對話後，上次的對話會結束，仍可在對話紀錄裡閱讀。")
                        .font(.tujiBodySm)
                        .foregroundStyle(.tujiInk3)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(Space.s4)
        }
    }

    /// Opened without a topic: picking one starts the conversation.
    private var topicChoice: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: Space.s2) {
                Text("選一個圖鑑主題")
                    .font(.tujiH2)
                    .foregroundStyle(.tujiInk)
                    .accessibilityAddTraits(.isHeader)
                Text("Moira 會用這個主題的詞先開口，你跟著換個詞說說看。")
                    .font(.tujiBodySm)
                    .foregroundStyle(.tujiInk2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(Space.s4)
            TopicChoiceList(current: nil, rowBackground: .tujiPaper, pick: { topicId in
                Task { await self.model.startNew(topicId: topicId) }
            }, footer: { EmptyView() })
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
        }
    }

    @ViewBuilder
    private func failedState(_ failure: TopicChatModel.Failure) -> some View {
        switch failure {
        case .membership:
            MascotEmptyState(
                pose: .peek,
                title: "主題對話是會員功能",
                message: "成為永久會員就能用罐頭點數和 Moira 聊天。"
            ) {
                BBtn(title: "了解會員") { self.presentPaywall() }
            }
            .frame(maxHeight: .infinity)
        default:
            VStack(spacing: Space.s3) {
                Mascot(pose: .sleep, size: 96)
                Text("現在聊不了")
                    .font(.tujiH3)
                    .foregroundStyle(.tujiInk)
                Text(verbatim: Self.sentence(for: failure))
                    .font(.tujiBody)
                    .foregroundStyle(.tujiInk2)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                if failure != .signedOut {
                    BBtn(title: "再試一次") {
                        Task { await self.model.load() }
                    }
                }
            }
            .padding(Space.s5)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: - 對話

    private var conversation: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: Space.s4) {
                    ForEach(self.model.state?.messages ?? []) { message in
                        self.row(message).id(message.id)
                    }
                    self.tail
                    Color.clear.frame(height: 1).id(Self.bottomID)
                }
                .padding(.horizontal, Space.s4)
                .padding(.vertical, Space.s4)
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: self.scrollKey) {
                withAnimation(self.reduceMotion ? nil : Motion.ease(Motion.d2)) {
                    proxy.scrollTo(self.model.latestTurn?.id ?? Self.bottomID, anchor: .top)
                }
            }
            .onAppear {
                proxy.scrollTo(Self.bottomID, anchor: .bottom)
            }
        }
    }

    private static let bottomID = "topic-chat-bottom"

    /// What moves the conversation along: a new message, or something waiting under it.
    private var scrollKey: String {
        "\(self.model.state?.messages.last?.id ?? "")|\(self.model.outgoing?.requestId ?? "")|\(self.model.work.map { "\($0)" } ?? "")"
    }

    @ViewBuilder
    private func row(_ message: ChatMessage) -> some View {
        switch message.kind {
        case .topic:
            TopicDividerRow(name: message.topic?.name ?? message.topicId)
        case .user:
            UserTurnRow(text: message.user?.text ?? "")
        case .ai:
            if let turn = message.ai {
                let isLatest = self.model.isActive && message.id == self.model.latestTurn?.id && !self.model.isWriting
                AITurnRow(
                    turn: turn,
                    language: self.targetLanguage,
                    showTranslation: self.model.showTranslation,
                    showReading: self.model.showReading,
                    isLatest: isLatest,
                    hintShown: isLatest && self.model.hintShown,
                    exampleShown: isLatest && self.model.exampleShown,
                    words: turn.wordIds.compactMap { self.words.find(id: $0) },
                    fill: { text, support in self.model.fill(text, support: support) },
                    lookUp: { self.lookedUp = $0 }
                )
            }
        }
    }

    /// Everything after the last saved message: the answer on its way, the
    /// topic being opened, a failure, the review.
    @ViewBuilder
    private var tail: some View {
        if let outgoing = self.model.outgoing {
            OutgoingRow(outgoing: outgoing, retry: self.model.retryOutgoing, edit: self.model.editOutgoing)
        }
        if self.model.isWriting || self.model.work != nil {
            self.writingRow
        } else if self.model.state?.needsOpening == true, self.model.isActive {
            self.notice("話題的開場沒有出現。主題已經換好了。") {
                Button("重試開場") { Task { await self.model.retryOpening() } }
                    .buttonStyle(.plain)
                    .font(.tujiBodySm(.strong))
                    .foregroundStyle(.tujiInk)
                    .frame(minHeight: 44)
            }
        }
        if let failure = self.model.actionFailure {
            self.notice(Self.sentence(for: failure)) {
                if failure == .insufficientPoints {
                    NavigationLink(value: NavRoute.creditStatement) {
                        Text("點數明細").font(.tujiBodySm(.strong)).foregroundStyle(.tujiInk)
                    }
                    .frame(minHeight: 44)
                }
                Button("知道了") { self.model.clearActionFailure() }
                    .buttonStyle(.plain)
                    .font(.tujiBodySm)
                    .foregroundStyle(.tujiInk3)
                    .frame(minHeight: 44)
            }
        }
        if let chat = self.model.chat, !chat.isActive {
            ChatReviewSection(
                chat: chat,
                failed: self.model.state?.reviewError != nil,
                showTranslation: self.model.showTranslation,
                showReading: self.model.showReading,
                retry: { Task { await self.model.end(review: true) } }
            )
        }
    }

    private var writingRow: some View {
        HStack(spacing: Space.s2) {
            Mascot(pose: .think, size: 28)
            TujiProgressBar(progress: nil).frame(width: 40)
            Text(verbatim: self.writingLabel)
                .font(.tujiBodySm)
                .foregroundStyle(.tujiInk3)
        }
        .accessibilityElement(children: .combine)
    }

    private var writingLabel: String {
        switch self.model.work {
        case .starting: tujiLocalized("Moira 正在準備話題…")
        case let .switching(topicId): tujiLocalized("正在換到「\(self.topicName(topicId))」…")
        case .opening: tujiLocalized("Moira 正在開場…")
        case .simplify: tujiLocalized("Moira 正在把問題說簡單一點…")
        case .another: tujiLocalized("Moira 正在換個問題…")
        case .ending: tujiLocalized("正在整理回顧…")
        case nil: tujiLocalized("Moira 正在回覆…")
        }
    }

    private func notice(_ text: String, @ViewBuilder actions: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: Space.s1) {
            Text(verbatim: text)
                .font(.tujiBodySm)
                .foregroundStyle(.tujiInk2)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: Space.s4) { actions() }
        }
        .padding(Space.s3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.tujiPaper2)
    }

    // MARK: - 輸入

    private var composer: some View {
        VStack(spacing: Space.s2) {
            if let kept = self.model.keptDraft {
                HStack(spacing: Space.s3) {
                    Text("已保留「\(kept.topicName)」的草稿")
                        .font(.tujiBodySm)
                        .foregroundStyle(.tujiInk2)
                        .lineLimit(2)
                    Spacer(minLength: Space.s2)
                    Button("帶入") { self.model.restoreKeptDraft() }
                        .font(.tujiBodySm(.strong))
                    Button("清除") { self.model.discardKeptDraft() }
                        .font(.tujiBodySm)
                        .foregroundStyle(.tujiInk3)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.tujiInk)
                .frame(minHeight: 44)
            }
            if self.supportsOpen {
                SupportTray(model: self.model) { kind in
                    switch kind {
                    case .express:
                        self.expressing = true
                    case .simplify, .another:
                        self.supportsOpen = false
                        Task { await self.model.assist(kind) }
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
            HStack(alignment: .bottom, spacing: Space.s2) {
                Button {
                    withAnimation(self.reduceMotion ? nil : Motion.ease(Motion.d1)) {
                        self.supportsOpen.toggle()
                    }
                } label: {
                    Image(systemName: self.supportsOpen ? "xmark" : "lightbulb")
                        .font(.tujiIcon(17, weight: .semibold))
                        .foregroundStyle(.tujiInk)
                        .frame(width: 52, height: 52)
                        .background(self.supportsOpen ? Color.tujiBrandPrimary : .tujiPaper2)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("幫我接話"))

                TextField("用學習的語言回答，或打中文也可以", text: self.$model.draft, axis: .vertical)
                    .lineLimit(1...4)
                    .focused(self.$fieldFocused)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .font(.tujiBody)
                    .foregroundStyle(.tujiInk)
                    .tint(.tujiInk)
                    .padding(.horizontal, Space.s3)
                    .padding(.vertical, Space.s3)
                    .frame(minHeight: 52)
                    .background(.tujiPaper2)
                    .overlay {
                        if self.fieldFocused {
                            Rectangle().stroke(.tujiCurrent, lineWidth: Border.bw2)
                        }
                    }

                self.sendButton
            }
            Text(verbatim: self.priceLine)
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

    @ViewBuilder
    private var sendButton: some View {
        if self.model.outgoing?.status == .sending {
            Button {
                Task { await self.model.stop() }
            } label: {
                Image(systemName: "stop.fill")
                    .font(.tujiIcon(15, weight: .bold))
                    .foregroundStyle(Color.tujiPaper)
                    .frame(width: 52, height: 52)
                    .background(Color.tujiInk)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("停止"))
        } else {
            let enabled = self.model.canSend && self.model.canAfford
            Button {
                self.supportsOpen = false
                self.model.send()
            } label: {
                Image(systemName: "arrow.up")
                    .font(.tujiIcon(17, weight: .bold))
                    .foregroundStyle(enabled ? Color.tujiPaper : .tujiInk3)
                    .frame(width: 52, height: 52)
                    .background(enabled ? Color.tujiInk : .tujiPaper2)
            }
            .buttonStyle(.plain)
            .disabled(!enabled)
            .accessibilityLabel(Text("送出"))
        }
    }

    /// Said before the tap: what a reply costs, what is left, and what is free.
    private var priceLine: String {
        guard let offer = self.model.state?.offer else { return "" }
        if offer.available < offer.maxPoints {
            return tujiLocalized("罐頭點數剩 \(offer.available) 點，不夠送出回答（每次最多 \(offer.maxPoints) 點）。")
        }
        return tujiLocalized("每次回覆 \(offer.minPoints)–\(offer.maxPoints) 點 · 剩 \(offer.available) 點 · 提示和開場不扣點")
    }

    private var endedFooter: some View {
        HStack(spacing: Space.s3) {
            if let topicId = self.model.chat?.topicId {
                BBtn(title: "用這個主題再聊", fullWidth: true) {
                    Task { await self.model.startNew(topicId: topicId) }
                }
            }
        }
        .padding(.horizontal, Space.s4)
        .padding(.vertical, Space.s3)
        .background(alignment: .top) {
            Rectangle().fill(.tujiRule).frame(height: Border.bw1)
        }
    }

    // MARK: - 文案

    static func sentence(for failure: TopicChatModel.Failure) -> String {
        switch failure {
        case .insufficientPoints: tujiLocalized("罐頭點數不夠，這次沒有送出。沒有扣點。")
        case .rateLimited: tujiLocalized("聊得有點快，等一下再試。沒有扣點。")
        case .busy: tujiLocalized("Moira 還在回覆上一則，等她說完再送。")
        case .offline: tujiLocalized("連不上網路。你的回答還在，可以再送一次。")
        case .membership: tujiLocalized("主題對話是會員功能。")
        case .signedOut: tujiLocalized("請先登入再開始對話。")
        case .unavailable: tujiLocalized("現在不能使用主題對話。")
        case .topicUnavailable: tujiLocalized("這個圖鑑暫時不能當主題，換一個試試。")
        case .outdated: tujiLocalized("對話已經往前了，請回答最新的問題。")
        case .assistLimit: tujiLocalized("這一題的免費輔助用完了。已經生成的提示還在，也可以直接回答。")
        case .ended: tujiLocalized("這段對話已經結束。")
        case .failed: tujiLocalized("Moira 這次沒有回好，再試一次。沒有扣點。")
        }
    }
}
