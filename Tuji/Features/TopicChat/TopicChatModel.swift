// 圖鑑主題對話 — what the screen holds between the server's answers.
//
// The server owns the conversation (`TopicChatState`) and decides every race;
// this model owns only what has not reached it yet: the draft, the answer on
// its way (`Outgoing`), which supports were opened for the draft, and the
// draft kept from the topic before. Every action ends by drawing the state the
// server sent back, so nothing here has to guess whether a reply landed.
//
// Product rules this keeps (docs/ATLAS_AI_CONVERSATION_DESIGN.md):
// - Nothing is ever sent for the person: options, the example and 幫我表達
//   only fill the draft, and a draft that already holds something asks first.
// - One answer at a time. While it is written the draft stays editable and
//   sending waits; 停止 stops it, and a stopped or failed answer can be sent
//   again under the same request id (never charged twice) or taken back to edit.
// - Switching topic keeps the conversation and sets the draft aside rather
//   than leaving an old answer under a new question.

import Foundation
import Observation

/// Where 主題對話 was opened from.
enum TopicChatEntry: Hashable {
    /// A category page's 「用這個主題聊聊」.
    case topic(String)
    /// A saved conversation from 對話紀錄.
    case saved(chatId: String)
    /// The assistant home's 主題對話: no topic yet, so the person picks one.
    case choose
}

@MainActor
@Observable
final class TopicChatModel {
    enum Failure: Equatable {
        case insufficientPoints
        case rateLimited
        /// Something else is being written in this conversation.
        case busy
        case offline
        /// Not a 罐頭點數 account.
        case membership
        case signedOut
        /// The feature is off, or the conversation is gone.
        case unavailable
        case topicUnavailable
        /// The turn being answered is no longer the latest.
        case outdated
        case assistLimit
        case ended
        case failed
    }

    enum Phase: Equatable {
        case idle
        case loading
        /// There is a conversation to continue; ask before starting another.
        case choosing(TopicChatSummary)
        /// No topic yet: the person picks one, and that starts the conversation.
        case picking
        case ready
        case failed(Failure)
    }

    /// The answer on its way, kept until the server's state shows it landed.
    struct Outgoing: Equatable {
        enum Status: Equatable {
            case sending
            case stopped
            case failed(Failure)
        }

        let requestId: String
        let text: String
        let support: [ChatSupport]
        let replyTo: String
        var status: Status
    }

    /// What is being generated besides an answer.
    enum Work: Equatable {
        case starting
        case opening
        case switching(topicId: String)
        case simplify
        case another
        case ending
    }

    /// A draft set aside when the topic changed.
    struct KeptDraft: Equatable {
        let topicName: String
        let text: String
    }

    /// An answer waiting for the person to say whether it replaces the draft.
    struct PendingFill: Equatable {
        let text: String
        let support: ChatSupport
    }

    /// 幫我表達's panel.
    struct Express: Equatable {
        var idea = ""
        var result: ChatTargetText?
        var working = false
        var failure: Failure?
        /// One id per (turn, idea), reused when the same idea is asked again.
        var request: Request?

        struct Request: Equatable {
            let messageId: String
            let idea: String
            let requestId: String
        }
    }

    private(set) var phase: Phase = .idle
    private(set) var state: TopicChatState?
    var draft = ""
    private(set) var draftSupport: Set<ChatSupport> = []
    private(set) var outgoing: Outgoing?
    private(set) var work: Work?
    /// Why the last switch, assist, opening or end did not happen.
    private(set) var actionFailure: Failure?
    private(set) var keptDraft: KeptDraft?
    private(set) var pendingFill: PendingFill?
    var express = Express()
    /// The latest turn's 給我提示 and 示範回答, opened or not.
    private(set) var hintShown = false
    private(set) var exampleShown = false
    private(set) var history: [TopicChatSummary] = []

    var showTranslation: Bool {
        didSet { self.defaults.set(self.showTranslation, forKey: Self.translationKey) }
    }

    var showReading: Bool {
        didSet { self.defaults.set(self.showReading, forKey: Self.readingKey) }
    }

    let entry: TopicChatEntry
    private let repository: TopicChatting
    private let language: LanguageContext
    private let defaults: UserDefaults
    private let makeRequestId: @MainActor () -> String
    private let pollInterval: Duration
    private var replyTask: Task<Void, Never>?
    /// Bumped by every switch: only the newest one's answer is drawn.
    private var switchToken = 0
    private var hintTurnId: String?

    static let translationKey = "tuji.topicChat.showTranslation"
    static let readingKey = "tuji.topicChat.showReading"

    init(
        entry: TopicChatEntry,
        repository: TopicChatting = LiveTopicChatRepository(),
        language: LanguageContext = SettingsStore.shared,
        defaults: UserDefaults = .standard,
        makeRequestId: @escaping @MainActor () -> String = { UUID().uuidString.lowercased() },
        pollInterval: Duration = .seconds(2)
    ) {
        self.entry = entry
        self.repository = repository
        self.language = language
        self.defaults = defaults
        self.makeRequestId = makeRequestId
        self.pollInterval = pollInterval
        // A beginner reads the translation by default; either can be turned off.
        self.showTranslation = defaults.object(forKey: Self.translationKey) as? Bool ?? true
        self.showReading = defaults.object(forKey: Self.readingKey) as? Bool ?? true
    }

    // MARK: - 讀

    private var uiLanguage: String {
        UILanguage(code: self.language.uiLang).rawValue
    }

    private var direction: String {
        self.language.learningDirection.rawValue
    }

    var chat: TopicChatSummary? {
        self.state?.chat
    }

    var isActive: Bool {
        self.chat?.isActive ?? false
    }

    /// The turn the person is answering; only it offers answer actions.
    var latestTurn: ChatMessage? {
        self.state?.latestTurn
    }

    var isWriting: Bool {
        self.outgoing?.status == .sending || self.state?.pending != nil
    }

    var canSend: Bool {
        self.isActive && self.latestTurn != nil && !self.isWriting && self.work == nil
            && !self.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// The ceiling, not the floor: the server refuses a balance below what a reply may cost.
    var canAfford: Bool {
        guard let offer = self.state?.offer else { return false }
        return offer.available >= offer.maxPoints
    }

    var canAssist: Bool {
        self.isActive && self.latestTurn != nil && !self.isWriting && self.work == nil
            && (self.state?.assistsLeft ?? 0) > 0
    }

    // MARK: - 進入

    func load() async {
        guard self.phase == .idle || self.isFailed else { return }
        self.phase = .loading
        do {
            switch self.entry {
            case let .saved(chatId):
                try await self.apply(self.repository.read(id: chatId, uiLanguage: self.uiLanguage))
                self.phase = .ready
            case let .topic(topicId):
                let list = try await self.repository.list(learning: self.direction, uiLanguage: self.uiLanguage)
                self.history = list.chats
                if let active = list.chats.first(where: { $0.id == list.active }) {
                    self.phase = .choosing(active)
                } else {
                    await self.startNew(topicId: topicId)
                    return
                }
            case .choose:
                let list = try await self.repository.list(learning: self.direction, uiLanguage: self.uiLanguage)
                self.history = list.chats
                if let active = list.chats.first(where: { $0.id == list.active }) {
                    self.phase = .choosing(active)
                } else {
                    self.phase = .picking
                }
                return
            }
        } catch {
            self.phase = .failed(Self.failure(for: error))
            return
        }
        await self.pollWhilePending()
    }

    private var isFailed: Bool {
        if case .failed = self.phase { return true }
        return false
    }

    /// 繼續上次.
    func continueActive() async {
        guard case let .choosing(active) = self.phase else { return }
        self.phase = .loading
        do {
            try await self.apply(self.repository.read(id: active.id, uiLanguage: self.uiLanguage))
            self.phase = .ready
        } catch {
            self.phase = .failed(Self.failure(for: error))
            return
        }
        await self.pollWhilePending()
    }

    /// 開始新對話 when no topic came with the entry: pick one first.
    func pickNewTopic() {
        guard case .choosing = self.phase else { return }
        self.phase = .picking
    }

    /// A new conversation on `topicId`. The one being continued in this direction ends, without a review.
    func startNew(topicId: String) async {
        self.cancelReply()
        self.outgoing = nil
        self.draft = ""
        self.draftSupport = []
        self.keptDraft = nil
        self.actionFailure = nil
        if self.state == nil { self.phase = .loading }
        self.work = .starting
        defer { self.work = nil }
        do {
            let state = try await self.repository.start(TopicChatStartBody(
                requestId: self.makeRequestId(),
                uiLanguage: self.uiLanguage,
                learningDirection: self.direction,
                topicId: topicId
            ))
            self.apply(state)
            self.phase = .ready
        } catch {
            if self.state == nil {
                self.phase = .failed(Self.failure(for: error))
            } else {
                self.actionFailure = Self.failure(for: error)
            }
        }
    }

    /// Re-reads the conversation, e.g. after a stop or on returning to the screen.
    func refresh() async {
        guard let chat else { return }
        do {
            try await self.apply(self.repository.read(id: chat.id, uiLanguage: self.uiLanguage))
        } catch {
            // What is on screen stays; the next action reports.
        }
    }

    /// Something is being written that this screen did not start, or whose
    /// answer was lost: ask again until it lands or stops.
    private func pollWhilePending() async {
        var tries = 0
        while self.state?.pending != nil, tries < 60, !Task.isCancelled {
            tries += 1
            try? await Task.sleep(for: self.pollInterval)
            if Task.isCancelled { return }
            await self.refresh()
        }
        self.settleOutgoing()
    }

    // MARK: - 回答

    /// Sends the draft, or sends again an answer that failed or was stopped.
    func send() {
        guard self.canSend, let turn = self.latestTurn else { return }
        let text = self.draft.trimmingCharacters(in: .whitespacesAndNewlines)
        let support = ChatSupport.allCases.filter { self.draftSupport.contains($0) }
        self.outgoing = Outgoing(
            requestId: self.makeRequestId(), text: text, support: support, replyTo: turn.id, status: .sending
        )
        self.draft = ""
        self.draftSupport = []
        self.runOutgoing()
    }

    /// 再送一次: the same answer under the same request id — never a second message or charge.
    func retryOutgoing() {
        guard var outgoing, outgoing.status != .sending, self.isActive else { return }
        outgoing.status = .sending
        self.outgoing = outgoing
        self.runOutgoing()
    }

    /// 改一下: the answer goes back into the draft, and the old request is let go.
    func editOutgoing() {
        guard let outgoing, outgoing.status != .sending else { return }
        self.draft = outgoing.text
        self.draftSupport = Set(outgoing.support)
        self.outgoing = nil
    }

    private func runOutgoing() {
        guard let outgoing, let chat else { return }
        self.replyTask?.cancel()
        self.replyTask = Task {
            do {
                let state = try await self.repository.reply(id: chat.id, TopicChatReplyBody(
                    requestId: outgoing.requestId,
                    uiLanguage: self.uiLanguage,
                    text: outgoing.text,
                    replyTo: outgoing.replyTo,
                    support: outgoing.support.map(\.rawValue)
                ))
                if Task.isCancelled { return }
                self.apply(state)
                await self.pollWhilePending()
            } catch {
                if Task.isCancelled { return }
                let failure = Self.failure(for: error)
                if failure == .outdated || failure == .ended {
                    // The turn moved on; the answer goes back to the draft rather than nowhere.
                    if self.draft.isEmpty { self.draft = outgoing.text }
                    self.outgoing = nil
                    await self.refresh()
                } else if failure == .busy {
                    // Another device or an earlier send is writing; wait for it, then retry is offered.
                    await self.refresh()
                    await self.pollWhilePending()
                    self.markOutgoing(.failed(.busy))
                } else {
                    self.markOutgoing(.failed(failure))
                }
            }
        }
    }

    private func markOutgoing(_ status: Outgoing.Status) {
        guard var outgoing = self.outgoing, outgoing.status == .sending || status != .sending else { return }
        outgoing.status = status
        self.outgoing = outgoing
    }

    /// The server's state says what became of the answer: it landed (a newer turn
    /// exists), it is still being written, or it did not land and stays to be retried.
    private func settleOutgoing() {
        guard let outgoing else { return }
        if self.latestTurn?.id != outgoing.replyTo, self.latestTurn != nil {
            self.outgoing = nil
        } else if self.state?.pending?.requestId != outgoing.requestId, outgoing.status == .sending {
            self.markOutgoing(.stopped)
        }
    }

    /// 停止. Whichever the server sees first wins: a reply that already landed stays.
    func stop() async {
        guard let outgoing, outgoing.status == .sending, let chat else { return }
        self.cancelReply()
        self.markOutgoing(.stopped)
        _ = try? await self.repository.stop(id: chat.id, requestId: outgoing.requestId)
        await self.refresh()
        self.settleOutgoing()
    }

    private func cancelReply() {
        self.replyTask?.cancel()
        self.replyTask = nil
    }

    // MARK: - 草稿

    /// An option, the example, a word or 幫我表達's sentence. Never sends; a
    /// draft that already holds something asks before it is replaced.
    func fill(_ text: String, support: ChatSupport) {
        let current = self.draft.trimmingCharacters(in: .whitespacesAndNewlines)
        if current.isEmpty || current == text {
            self.draft = text
            self.draftSupport.insert(support)
        } else {
            self.pendingFill = PendingFill(text: text, support: support)
        }
    }

    enum FillChoice {
        case replace, append, cancel
    }

    func resolveFill(_ choice: FillChoice) {
        guard let pendingFill else { return }
        self.pendingFill = nil
        switch choice {
        case .replace:
            self.draft = pendingFill.text
        case .append:
            let joiner = self.language.learningDirection.targetLanguage == .ja ? "" : " "
            self.draft = self.draft.trimmingCharacters(in: .whitespacesAndNewlines) + joiner + pendingFill.text
        case .cancel:
            return
        }
        self.draftSupport.insert(pendingFill.support)
    }

    func restoreKeptDraft() {
        guard let keptDraft else { return }
        self.fill(keptDraft.text, support: .hint)
        // Taking back one's own words is not help.
        self.draftSupport.remove(.hint)
        self.keptDraft = nil
    }

    func discardKeptDraft() {
        self.keptDraft = nil
    }

    // MARK: - 幫我接話

    /// 給我提示 — what was generated with the turn; no request, no charge.
    func toggleHint() {
        self.syncTurnSupports()
        self.hintShown.toggle()
        if self.hintShown { self.draftSupport.insert(.hint) }
    }

    /// 示範回答 — likewise.
    func toggleExample() {
        self.syncTurnSupports()
        self.exampleShown.toggle()
        if self.exampleShown { self.draftSupport.insert(.example) }
    }

    /// A newer turn closes what was opened under the old one.
    private func syncTurnSupports() {
        let id = self.latestTurn?.id
        if id != self.hintTurnId {
            self.hintTurnId = id
            self.hintShown = false
            self.exampleShown = false
        }
    }

    /// 簡單一點 / 換個問題 — free, two between answers, shared with 幫我表達.
    func assist(_ kind: TopicChatAssistKind) async {
        guard kind != .express, self.canAssist, let chat, let turn = self.latestTurn else { return }
        self.work = kind == .simplify ? .simplify : .another
        self.actionFailure = nil
        defer { self.work = nil }
        do {
            let state = try await self.repository.assist(id: chat.id, TopicChatAssistBody(
                kind: kind, requestId: self.makeRequestId(), uiLanguage: self.uiLanguage,
                messageId: turn.id, text: nil
            ))
            self.apply(state)
            if kind == .simplify { self.draftSupport.insert(.simplify) }
        } catch {
            self.actionFailure = Self.failure(for: error)
            await self.refresh()
        }
    }

    /// 幫我表達 — the person's idea in their own words, back as one sentence to bring into the draft.
    func expressIdea() async {
        let idea = self.express.idea.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !idea.isEmpty, !self.express.working, let chat, let turn = self.latestTurn else { return }
        var requestId = self.makeRequestId()
        if let earlier = self.express.request, earlier.messageId == turn.id, earlier.idea == idea {
            requestId = earlier.requestId
        }
        self.express.request = Express.Request(messageId: turn.id, idea: idea, requestId: requestId)
        self.express.working = true
        self.express.failure = nil
        defer { self.express.working = false }
        do {
            let state = try await self.repository.assist(id: chat.id, TopicChatAssistBody(
                kind: .express, requestId: requestId, uiLanguage: self.uiLanguage, messageId: turn.id, text: idea
            ))
            self.apply(state)
            self.express.result = state.express
            if state.express == nil { self.express.failure = .failed }
        } catch {
            self.express.failure = Self.failure(for: error)
        }
    }

    /// 帶入回答.
    func useExpressed() {
        guard let result = self.express.result else { return }
        self.fill(result.text, support: .express)
        self.express = Express()
    }

    func closeExpress() {
        self.express = Express()
    }

    // MARK: - 換主題

    /// 更換圖鑑. The conversation stays; the draft is set aside; an answer still
    /// being written is let go (the server will not land it under the new topic).
    func switchTopic(to topicId: String) async {
        guard self.isActive, let chat, topicId != chat.topicId else { return }
        if let outgoing {
            self.cancelReply()
            let text = self.draft.isEmpty ? outgoing.text : self.draft
            self.draft = text
            self.outgoing = nil
        }
        let aside = self.draft.trimmingCharacters(in: .whitespacesAndNewlines)
        if !aside.isEmpty {
            self.keptDraft = KeptDraft(topicName: chat.topicName, text: aside)
            self.draft = ""
            self.draftSupport = []
        }
        self.switchToken += 1
        let token = self.switchToken
        self.work = .switching(topicId: topicId)
        self.actionFailure = nil
        do {
            let state = try await self.repository.switchTopic(
                id: chat.id, requestId: self.makeRequestId(), uiLanguage: self.uiLanguage, topicId: topicId
            )
            guard token == self.switchToken else { return }
            self.apply(state)
            self.work = nil
        } catch {
            guard token == self.switchToken else { return }
            self.work = nil
            self.actionFailure = Self.failure(for: error)
            await self.refresh()
        }
    }

    /// 重試開場 — after a switch whose opening failed. The topic stays switched.
    func retryOpening() async {
        guard let chat, self.state?.needsOpening == true, self.work == nil else { return }
        self.work = .opening
        self.actionFailure = nil
        defer { self.work = nil }
        do {
            try await self.apply(self.repository.retryOpening(
                id: chat.id, requestId: self.makeRequestId(), uiLanguage: self.uiLanguage
            ))
        } catch {
            self.actionFailure = Self.failure(for: error)
        }
    }

    // MARK: - 結束

    /// 結束並回顧 (or just 結束). The review is made only when the person answered.
    func end(review: Bool) async {
        guard let chat, self.work == nil else { return }
        self.cancelReply()
        self.outgoing = nil
        self.work = .ending
        self.actionFailure = nil
        defer { self.work = nil }
        do {
            try await self.apply(self.repository.end(
                id: chat.id, requestId: self.makeRequestId(), uiLanguage: self.uiLanguage, review: review
            ))
        } catch {
            self.actionFailure = Self.failure(for: error)
        }
    }

    func loadHistory() async {
        do {
            self.history = try await self.repository.list(learning: self.direction, uiLanguage: self.uiLanguage).chats
        } catch {
            // The list keeps what it had.
        }
    }

    func delete(chatId: String) async -> Bool {
        do {
            try await self.repository.delete(id: chatId)
            self.history.removeAll { $0.id == chatId }
            if self.chat?.id == chatId {
                self.cancelReply()
                self.state = nil
                self.outgoing = nil
            }
            return true
        } catch {
            self.actionFailure = Self.failure(for: error)
            return false
        }
    }

    func clearActionFailure() {
        self.actionFailure = nil
    }

    /// Leaving the screen: the answer being written is not waited for. It lands
    /// or not on the server, and is there to read on the way back.
    func leave() {
        self.cancelReply()
    }

    // MARK: - Bits

    private func apply(_ state: TopicChatState) {
        self.state = state
        self.syncTurnSupports()
        self.settleOutgoing()
    }

    static func failure(for error: Error) -> Failure {
        switch error {
        case let APIError.conflict(reason, _):
            switch reason {
            case "insufficient_credits": .insufficientPoints
            case "chat_busy": .busy
            case "message_outdated", "request_stale": .outdated
            case "assist_limit": .assistLimit
            case "chat_ended": .ended
            case "topic_unavailable": .topicUnavailable
            default: .failed
            }
        case APIError.rateLimited:
            .rateLimited
        case APIError.transport:
            .offline
        case APIError.forbidden:
            .membership
        case APIError.unauthorized:
            .signedOut
        case APIError.notFound:
            .unavailable
        default:
            .failed
        }
    }
}
