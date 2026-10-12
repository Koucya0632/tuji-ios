// 助手's one call that costs something — tuji-web `/api/assistant/ask`.
//
// Everything else 助手 answers comes from the device. This is the question the
// device could not answer, sent to a model, and it is paid in 罐頭點數: the
// server prices an answer by the tokens it used, between `minPoints` and
// `maxPoints`, and charges nothing when it declines or fails.

import Foundation

/// What asking costs and what the account holds, read before the first question.
struct AssistantOffer: Decodable, Equatable {
    let minPoints: Int
    let maxPoints: Int
    let available: Int
}

struct AssistantTurn: Encodable, Equatable {
    enum Role: String, Encodable {
        case user, assistant
    }

    let role: Role
    let text: String
}

struct AssistantAskPayload: Encodable, Equatable {
    /// Kept across a resend of the same question: the server charges a request
    /// id once, so a retry after a lost response is not a second charge.
    let requestId: String
    let question: String
    let uiLanguage: String
    let learningDirection: String
    /// Catalogue ids only. The server reads the entries itself.
    let wordIds: [String]
    let history: [AssistantTurn]
}

struct AssistantAnswer: Decodable, Equatable {
    let answer: String
    /// False when the model declined: not a language-learning question.
    let inScope: Bool
    let wordIds: [String]
    let charged: Int
    let available: Int
    let minPoints: Int
    let maxPoints: Int
}

@MainActor
protocol AssistantAsking {
    func assistantOffer() async throws -> AssistantOffer
    func askAssistant(_ payload: AssistantAskPayload) async throws -> AssistantAnswer
}

@MainActor
struct LiveAssistantRepository: AssistantAsking {
    private let api: APIClient

    init(api: APIClient = .shared) {
        self.api = api
    }

    func assistantOffer() async throws -> AssistantOffer {
        try await self.api.get(.assistantOffer)
    }

    func askAssistant(_ payload: AssistantAskPayload) async throws -> AssistantAnswer {
        try await self.api.post(.assistantAsk, body: payload)
    }
}
