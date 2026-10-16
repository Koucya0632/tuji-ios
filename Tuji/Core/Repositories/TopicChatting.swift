// 圖鑑主題對話 — tuji-web `/api/topic-chat`.
//
// The person picks a 圖鑑 category as the topic; Moira opens, takes up what
// they say, and shows a sentence they can copy with one part swapped. The
// server keeps the conversation and decides every race: a reply lands only if
// its request is still pending, the topic has not changed and the message it
// answers is still the latest. So every action here answers with the whole
// conversation as the server now holds it, and the app draws that.
//
// Every generation carries a request id made here. Sending the same id again
// never makes a second message or a second charge — it is how a lost answer is
// asked about, and how a failed or stopped one is retried.

import Foundation

/// A sentence in the language being learned, with what helps read it.
struct ChatTargetText: Codable, Equatable, Hashable {
    let text: String
    /// Japanese only: kana over each kanji run.
    let furigana: [FuriganaSegment]?
    /// Japanese only, when there is no `furigana`: the whole sentence in kana.
    let reading: String?
    /// In the interface language; nil when that is the language being learned.
    let translation: String?
}

/// 「跟著說」: the structure behind a turn, with one blank (＿＿ or ___).
struct ChatPattern: Codable, Equatable {
    /// A fixed internal name, the same however the model words it.
    let key: String
    let template: String
    let translation: String?
}

/// An answer the person can drop into their draft: what fills the blank, and the whole sentence.
struct ChatOption: Codable, Equatable, Hashable {
    let label: String
    let answer: ChatTargetText
}

/// 「給我提示」: a word worth using now. `wordId` only when it is one of the topic's entries.
struct ChatKeyword: Codable, Equatable, Hashable {
    let text: String
    let reading: String?
    let meaning: String
    let wordId: String?
}

struct ChatAITurn: Codable, Equatable {
    /// 「簡單一點」: the same question again, easier, added under the turn.
    struct Simpler: Codable, Equatable {
        let note: String
        let line: ChatTargetText?
        let options: [ChatOption]
    }

    /// opening / share / follow_up / answer / clarify / role_invite / another.
    let intent: String
    /// Opening only: one line naming the imagined situation.
    let scene: String?
    let line: ChatTargetText
    /// False when the turn leaves room to talk rather than asking something.
    let awaitsAnswer: Bool
    let pattern: ChatPattern?
    /// 「示範回答」: one whole answer the person could send.
    let example: ChatTargetText?
    let options: [ChatOption]
    let keywords: [ChatKeyword]
    /// Topic entries to show as picture cards.
    let wordIds: [String]
    let simpler: Simpler?
}

/// What the app can say it helped with. The wire values are the server's.
enum ChatSupport: String, Codable, CaseIterable {
    case hint, example, express, option, simplify
}

struct ChatMessage: Codable, Equatable, Identifiable {
    enum Kind: String, Codable {
        case ai, user, topic
    }

    struct UserTurn: Codable, Equatable {
        let text: String
        let support: [String]
    }

    struct TopicMark: Codable, Equatable {
        let name: String
    }

    let id: String
    let kind: Kind
    let topicId: String
    let topicVersion: Int
    let ai: ChatAITurn?
    let user: UserTurn?
    let topic: TopicMark?
}

struct ChatReview: Codable, Equatable {
    struct Topic: Codable, Equatable {
        let id: String
        let name: String
    }

    struct Phrase: Codable, Equatable {
        /// "you": the person said it. "moira": Moira showed it.
        let source: String
        let text: ChatTargetText
        let messageId: String
    }

    let topics: [Topic]
    let phrases: [Phrase]
    /// 「下次可以試」 — a suggestion, not something the person did.
    let tryNext: ChatTargetText?
    let nextIdea: String
}

struct TopicChatSummary: Codable, Equatable, Identifiable {
    let id: String
    let learningDirection: String
    let topicId: String
    let topicName: String
    let topicVersion: Int
    /// "active" or "ended".
    let status: String
    let updatedAt: String
    /// How many times the person answered. Zero means no review is offered.
    let answers: Int
    /// Points this conversation's replies took. Nil from a server older than the field.
    let spent: Int?
    let review: ChatReview?

    var isActive: Bool {
        self.status == "active"
    }
}

struct TopicChatOffer: Codable, Equatable {
    let minPoints: Int
    let maxPoints: Int
    let available: Int
}

struct TopicChatPending: Codable, Equatable {
    let requestId: String
    /// opening / reply / another / simplify.
    let kind: String
    /// A reply's answer, so it can be shown waiting.
    let text: String?
}

/// The conversation as the server holds it, and what the last action added.
struct TopicChatState: Decodable, Equatable {
    let chat: TopicChatSummary
    let messages: [ChatMessage]
    let pending: TopicChatPending?
    /// The current topic has no opening yet: the last one failed.
    let needsOpening: Bool
    /// Free 幫我表達／簡單一點／換個問題 left before the next answer.
    let assistsLeft: Int
    let offer: TopicChatOffer
    /// Why the opening this action tried did not arrive.
    let openingError: String?
    /// Why the review this action tried did not arrive.
    let reviewError: String?
    /// 幫我表達's sentence.
    let express: ChatTargetText?
    /// Points a reply took.
    let charged: Int?

    /// The turn the person is answering: the newest AI turn of the current topic.
    var latestTurn: ChatMessage? {
        guard let last = self.messages.last(where: { $0.kind != .user }),
              last.kind == .ai, last.topicVersion == self.chat.topicVersion
        else { return nil }
        return last
    }
}

struct TopicChatList: Decodable, Equatable {
    let chats: [TopicChatSummary]
    /// The conversation to continue in this direction.
    let active: String?
    let offer: TopicChatOffer
}

struct TopicChatStartBody: Encodable, Equatable {
    let requestId: String
    let uiLanguage: String
    let learningDirection: String
    let topicId: String
}

struct TopicChatReplyBody: Encodable, Equatable {
    let requestId: String
    let uiLanguage: String
    let text: String
    let replyTo: String
    let support: [String]
}

enum TopicChatAssistKind: String, Encodable {
    case express, simplify, another
}

struct TopicChatAssistBody: Encodable, Equatable {
    let kind: TopicChatAssistKind
    let requestId: String
    let uiLanguage: String
    let messageId: String
    /// 幫我表達 only: what the person wants to say.
    let text: String?
}

@MainActor
protocol TopicChatting {
    func list(learning: String, uiLanguage: String) async throws -> TopicChatList
    func start(_ body: TopicChatStartBody) async throws -> TopicChatState
    func read(id: String, uiLanguage: String) async throws -> TopicChatState
    func delete(id: String) async throws
    func switchTopic(id: String, requestId: String, uiLanguage: String, topicId: String) async throws -> TopicChatState
    func retryOpening(id: String, requestId: String, uiLanguage: String) async throws -> TopicChatState
    func reply(id: String, _ body: TopicChatReplyBody) async throws -> TopicChatState
    func assist(id: String, _ body: TopicChatAssistBody) async throws -> TopicChatState
    /// True when the server stopped it; false when it had already landed or failed.
    func stop(id: String, requestId: String) async throws -> Bool
    func end(id: String, requestId: String, uiLanguage: String, review: Bool) async throws -> TopicChatState
}

@MainActor
struct LiveTopicChatRepository: TopicChatting {
    private let api: APIClient

    init(api: APIClient = .shared) {
        self.api = api
    }

    private struct TopicBody: Encodable {
        let requestId: String
        let uiLanguage: String
        let topicId: String
    }

    private struct OpeningBody: Encodable {
        let requestId: String
        let uiLanguage: String
    }

    private struct StopBody: Encodable {
        let requestId: String
    }

    private struct Stopped: Decodable {
        let stopped: Bool
    }

    private struct EndBody: Encodable {
        let requestId: String
        let uiLanguage: String
        let review: Bool
    }

    func list(learning: String, uiLanguage: String) async throws -> TopicChatList {
        try await self.api.get(.topicChats(learning: learning, uiLanguage: uiLanguage))
    }

    func start(_ body: TopicChatStartBody) async throws -> TopicChatState {
        try await self.api.post(.topicChatStart, body: body)
    }

    func read(id: String, uiLanguage: String) async throws -> TopicChatState {
        try await self.api.get(.topicChat(id: id, uiLanguage: uiLanguage))
    }

    func delete(id: String) async throws {
        try await self.api.delete(.topicChat(id: id, uiLanguage: nil))
    }

    func switchTopic(
        id: String,
        requestId: String,
        uiLanguage: String,
        topicId: String
    ) async throws
        -> TopicChatState
    {
        try await self.api.post(
            .topicChatAction(id: id, action: "topic"),
            body: TopicBody(requestId: requestId, uiLanguage: uiLanguage, topicId: topicId)
        )
    }

    func retryOpening(id: String, requestId: String, uiLanguage: String) async throws -> TopicChatState {
        try await self.api.post(
            .topicChatAction(id: id, action: "opening"),
            body: OpeningBody(requestId: requestId, uiLanguage: uiLanguage)
        )
    }

    func reply(id: String, _ body: TopicChatReplyBody) async throws -> TopicChatState {
        try await self.api.post(.topicChatAction(id: id, action: "reply"), body: body)
    }

    func assist(id: String, _ body: TopicChatAssistBody) async throws -> TopicChatState {
        try await self.api.post(.topicChatAction(id: id, action: "assist"), body: body)
    }

    func stop(id: String, requestId: String) async throws -> Bool {
        let result: Stopped = try await self.api.post(
            .topicChatAction(id: id, action: "stop"),
            body: StopBody(requestId: requestId)
        )
        return result.stopped
    }

    func end(id: String, requestId: String, uiLanguage: String, review: Bool) async throws -> TopicChatState {
        try await self.api.post(
            .topicChatAction(id: id, action: "end"),
            body: EndBody(requestId: requestId, uiLanguage: uiLanguage, review: review)
        )
    }
}
