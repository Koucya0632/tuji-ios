// 圖鑑主題對話 — what the screen keeps between the server's answers.
//
// Assertions are on decisions (what was sent, under which request id, what the
// draft holds, which failure), never on a sentence: CI reads English and a
// laptop reads 繁體中文.

import Foundation
import Testing
@testable import Tuji

@MainActor
private final class TopicChatFake: TopicChatting {
    var chats: [TopicChatSummary] = []
    var active: String?
    var state: TopicChatState
    private(set) var replies: [TopicChatReplyBody] = []
    private(set) var assists: [TopicChatAssistBody] = []
    private(set) var stops: [String] = []
    private(set) var switches: [String] = []
    private(set) var starts: [TopicChatStartBody] = []
    var replyError: Error?
    var assistError: Error?
    var listError: Error?
    /// When set, a reply waits until `releaseReply()`.
    var holdsReply = false
    /// What a stop answers: true when the server stopped it before it landed.
    var stopLands = true
    private var waiting: CheckedContinuation<Void, Never>?

    init() {
        self.state = TopicChatFake.state(messages: [
            TopicChatFake.topic("t0"),
            TopicChatFake.ai("a1", line: "どこに行きたいですか？")
        ])
    }

    static func summary(
        id: String = "chat-1",
        topicId: String = "street",
        status: String = "active",
        answers: Int = 0
    )
        -> TopicChatSummary
    {
        TopicChatSummary(
            id: id, learningDirection: "zh-ja", topicId: topicId, topicName: topicId, topicVersion: 1,
            status: status, updatedAt: "2026-10-16T00:00:00Z", answers: answers, spent: 0, review: nil
        )
    }

    static func topic(_ id: String, topicId: String = "street") -> ChatMessage {
        ChatMessage(
            id: id,
            kind: .topic,
            topicId: topicId,
            topicVersion: 1,
            ai: nil,
            user: nil,
            topic: .init(name: topicId)
        )
    }

    static func ai(_ id: String, line: String, example: String? = "公園に行きたいです。") -> ChatMessage {
        let text = { (s: String) in ChatTargetText(text: s, furigana: nil, reading: nil, translation: "t") }
        return ChatMessage(id: id, kind: .ai, topicId: "street", topicVersion: 1, ai: ChatAITurn(
            intent: "share", scene: nil, line: text(line), awaitsAnswer: true,
            pattern: ChatPattern(key: "want_to_go", template: "＿＿に行きたいです。", translation: nil),
            example: example.map(text),
            options: [ChatOption(label: "公園", answer: text("公園に行きたいです。"))],
            keywords: [], wordIds: [], simpler: nil
        ), user: nil, topic: nil)
    }

    static func user(_ id: String, _ text: String) -> ChatMessage {
        ChatMessage(
            id: id,
            kind: .user,
            topicId: "street",
            topicVersion: 1,
            ai: nil,
            user: .init(text: text, support: []),
            topic: nil
        )
    }

    static func state(
        messages: [ChatMessage], chat: TopicChatSummary = summary(), pending: TopicChatPending? = nil,
        assistsLeft: Int = 2, available: Int = 100, express: ChatTargetText? = nil
    )
        -> TopicChatState
    {
        TopicChatState(
            chat: chat, messages: messages, pending: pending, needsOpening: false, assistsLeft: assistsLeft,
            offer: TopicChatOffer(minPoints: 1, maxPoints: 5, available: available),
            openingError: nil, reviewError: nil, express: express, charged: nil
        )
    }

    func releaseReply() {
        self.waiting?.resume()
        self.waiting = nil
    }

    func list(learning: String, uiLanguage: String) async throws -> TopicChatList {
        if let listError { throw listError }
        return TopicChatList(chats: self.chats, active: self.active, offer: self.state.offer)
    }

    func start(_ body: TopicChatStartBody) async throws -> TopicChatState {
        self.starts.append(body)
        return self.state
    }

    func read(id: String, uiLanguage: String) async throws -> TopicChatState {
        self.state
    }

    func delete(id: String) async throws {}

    func switchTopic(
        id: String,
        requestId: String,
        uiLanguage: String,
        topicId: String
    ) async throws
        -> TopicChatState
    {
        self.switches.append(topicId)
        let chat = TopicChatFake.summary(topicId: topicId)
        self.state = TopicChatFake.state(
            messages: self.state.messages + [TopicChatFake.topic("t-\(topicId)", topicId: topicId)],
            chat: chat
        )
        return self.state
    }

    func retryOpening(id: String, requestId: String, uiLanguage: String) async throws -> TopicChatState {
        self.state
    }

    func reply(id: String, _ body: TopicChatReplyBody) async throws -> TopicChatState {
        self.replies.append(body)
        if self.holdsReply {
            await withCheckedContinuation { self.waiting = $0 }
        }
        if let replyError { throw replyError }
        if self.stops.contains(body.requestId), self.stopLands { return self.state }
        self.state = TopicChatFake.state(messages: self.state.messages + [
            TopicChatFake.user("u\(self.replies.count)", body.text),
            TopicChatFake.ai("a\(self.replies.count + 1)", line: "re:\(body.text)")
        ])
        return self.state
    }

    func assist(id: String, _ body: TopicChatAssistBody) async throws -> TopicChatState {
        self.assists.append(body)
        if let assistError { throw assistError }
        if body.kind == .express {
            return TopicChatFake.state(
                messages: self.state.messages, assistsLeft: 1,
                express: ChatTargetText(text: "水を買いたいです。", furigana: nil, reading: nil, translation: "我想買水。")
            )
        }
        return self.state
    }

    func stop(id: String, requestId: String) async throws -> Bool {
        self.stops.append(requestId)
        return self.stopLands
    }

    func end(id: String, requestId: String, uiLanguage: String, review: Bool) async throws -> TopicChatState {
        self.state
    }
}

@MainActor
private final class RequestIds {
    private var issued = 0
    func next() -> String {
        self.issued += 1
        return "request-\(self.issued)"
    }
}

@MainActor
struct TopicChatModelTests {
    private let fake = TopicChatFake()
    private let ids = RequestIds()
    private let defaults = UserDefaults(suiteName: "topic-chat-\(UUID().uuidString)") ?? .standard

    private func makeModel(entry: TopicChatEntry = .topic("street")) -> TopicChatModel {
        TopicChatModel(
            entry: entry,
            repository: self.fake,
            language: FakeLanguageContext(uiLang: "zh-Hant", learningDirection: .zhJa),
            defaults: self.defaults,
            makeRequestId: self.ids.next,
            pollInterval: .milliseconds(1)
        )
    }

    private func readyModel() async -> TopicChatModel {
        let model = self.makeModel()
        await model.load()
        return model
    }

    /// Waits for the reply task to reach the fake.
    private func waitForReplies(_ count: Int) async {
        for _ in 0..<200 where self.fake.replies.count < count {
            await Task.yield()
        }
    }

    @Test
    func withNothingToContinueTheEntryTopicStartsAChat() async {
        let model = await self.readyModel()
        #expect(self.fake.starts.map(\.topicId) == ["street"])
        #expect(self.fake.starts.first?.learningDirection == "zh-ja")
        #expect(model.phase == .ready)
        #expect(model.latestTurn?.id == "a1")
    }

    @Test
    func openedWithoutATopicItAsksForOneBeforeStarting() async {
        let model = self.makeModel(entry: .choose)
        await model.load()
        #expect(model.phase == .picking)
        #expect(self.fake.starts.isEmpty)
        await model.startNew(topicId: "kitchen")
        #expect(self.fake.starts.map(\.topicId) == ["kitchen"])
        #expect(model.phase == .ready)
    }

    @Test
    func openedWithoutATopicAConversationToContinueStillComesFirst() async {
        self.fake.chats = [TopicChatFake.summary(topicId: "kitchen", answers: 3)]
        self.fake.active = "chat-1"
        let model = self.makeModel(entry: .choose)
        await model.load()
        guard case .choosing = model.phase else {
            Issue.record("expected the choice, got \(model.phase)")
            return
        }
        model.pickNewTopic()
        #expect(model.phase == .picking)
        #expect(self.fake.starts.isEmpty)
    }

    @Test
    func aConversationToContinueIsOfferedFirst() async {
        self.fake.chats = [TopicChatFake.summary(topicId: "kitchen", answers: 3)]
        self.fake.active = "chat-1"
        let model = await self.readyModel()
        guard case let .choosing(active) = model.phase else {
            Issue.record("expected the choice, got \(model.phase)")
            return
        }
        #expect(active.topicId == "kitchen")
        #expect(self.fake.starts.isEmpty)
        await model.continueActive()
        #expect(model.phase == .ready)
        #expect(self.fake.starts.isEmpty)
    }

    @Test
    func sendingTakesTheDraftAndRecordsTheSupportsUsed() async {
        let model = await self.readyModel()
        model.toggleExample()
        model.fill("公園に行きたいです。", support: .option)
        model.send()
        #expect(model.draft.isEmpty)
        #expect(model.outgoing?.status == .sending)
        await self.waitForReplies(1)
        for _ in 0..<50 where model.outgoing != nil {
            await Task.yield()
        }
        let sent = self.fake.replies.first
        #expect(sent?.text == "公園に行きたいです。")
        #expect(sent?.replyTo == "a1")
        #expect(sent?.support == ["example", "option"])
        #expect(model.outgoing == nil)
        #expect(model.latestTurn?.id == "a2")
        // A new turn closes what the old one opened.
        #expect(model.exampleShown == false)
    }

    @Test
    func aFailedAnswerIsSentAgainUnderTheSameRequestId() async {
        let model = await self.readyModel()
        self.fake.replyError = APIError.transport(URLError(.notConnectedToInternet))
        model.draft = "コンビニ"
        model.send()
        await self.waitForReplies(1)
        for _ in 0..<50 where model.outgoing?.status == .sending {
            await Task.yield()
        }
        #expect(model.outgoing?.status == .failed(.offline))
        self.fake.replyError = nil
        model.retryOutgoing()
        await self.waitForReplies(2)
        #expect(self.fake.replies.map(\.requestId) == ["request-2", "request-2"])
    }

    @Test
    func aStoppedAnswerCanBeTakenBackToEdit() async {
        let model = await self.readyModel()
        self.fake.holdsReply = true
        model.draft = "本屋"
        model.send()
        await self.waitForReplies(1)
        await model.stop()
        #expect(self.fake.stops == ["request-2"])
        #expect(model.outgoing?.status == .stopped)
        self.fake.releaseReply()
        model.editOutgoing()
        #expect(model.draft == "本屋")
        #expect(model.outgoing == nil)
    }

    @Test
    func aStopTheServerSawTooLateLeavesTheReply() async {
        let model = await self.readyModel()
        self.fake.holdsReply = true
        self.fake.stopLands = false
        model.draft = "駅"
        model.send()
        await self.waitForReplies(1)
        // The reply landed before the stop arrived.
        self.fake.state = TopicChatFake.state(messages: self.fake.state.messages + [
            TopicChatFake.user("u1", "駅"), TopicChatFake.ai("a2", line: "re:駅")
        ])
        await model.stop()
        self.fake.releaseReply()
        #expect(model.outgoing == nil)
        #expect(model.latestTurn?.id == "a2")
    }

    @Test
    func anAnswerDoesNotOverwriteADraftWithoutAsking() async {
        let model = await self.readyModel()
        model.draft = "自分の文"
        model.fill("公園に行きたいです。", support: .option)
        #expect(model.draft == "自分の文")
        #expect(model.pendingFill?.text == "公園に行きたいです。")
        model.resolveFill(.append)
        #expect(model.draft == "自分の文公園に行きたいです。")
        model.fill("駅", support: .hint)
        model.resolveFill(.replace)
        #expect(model.draft == "駅")
        model.fill("本屋", support: .hint)
        model.resolveFill(.cancel)
        #expect(model.draft == "駅")
    }

    @Test
    func switchingTopicSetsTheDraftAside() async {
        let model = await self.readyModel()
        model.draft = "パンを買いたい"
        await model.switchTopic(to: "zoo")
        #expect(self.fake.switches == ["zoo"])
        #expect(model.draft.isEmpty)
        #expect(model.keptDraft?.text == "パンを買いたい")
        #expect(model.keptDraft?.topicName == "street")
        #expect(model.chat?.topicId == "zoo")
        model.restoreKeptDraft()
        #expect(model.draft == "パンを買いたい")
        #expect(model.keptDraft == nil)
        // Picking the topic already on screen sends nothing.
        await model.switchTopic(to: "zoo")
        #expect(self.fake.switches == ["zoo"])
    }

    @Test
    func anAssistOverTheLimitIsReported() async {
        let model = await self.readyModel()
        self.fake.assistError = APIError.conflict(reason: "assist_limit", message: nil)
        await model.assist(.simplify)
        #expect(model.actionFailure == .assistLimit)
        #expect(model.work == nil)
    }

    @Test
    func theReadingSupportsAreRemembered() {
        let model = self.makeModel()
        #expect(model.showTranslation)
        model.showTranslation = false
        #expect(self.makeModel().showTranslation == false)
    }

    @Test
    func failuresAreToldApart() {
        #expect(TopicChatModel.failure(for: APIError.forbidden) == .membership)
        #expect(TopicChatModel
            .failure(for: APIError.conflict(reason: "insufficient_credits", message: nil)) == .insufficientPoints)
        #expect(TopicChatModel.failure(for: APIError.conflict(reason: "request_stale", message: nil)) == .outdated)
        #expect(TopicChatModel.failure(for: APIError.conflict(reason: "chat_busy", message: nil)) == .busy)
        #expect(TopicChatModel.failure(for: APIError.rateLimited(message: nil)) == .rateLimited)
        #expect(TopicChatModel.failure(for: APIError.unauthorized) == .signedOut)
    }

    @Test
    func aFailedListIsAFailedScreen() async {
        self.fake.listError = APIError.forbidden
        let model = await self.readyModel()
        #expect(model.phase == .failed(.membership))
    }
}
