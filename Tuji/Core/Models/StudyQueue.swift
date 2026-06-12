// Models for the study session — queue items, ratings, answer payloads.
// Maps directly to `DueCard` on the backend (lib/cards-db.ts) and the
// /api/study/answer body.

import Foundation

/// Lightweight word payload embedded in the queue item. Fields match the
/// snake_case backend → camelCase decoder rewrite.
struct StudyQueueWord: Decodable, Hashable, Identifiable {
    let id: String
    let word: String
    let chinese: String
    let imageUrl: String
    let pronunciation: String
    let category: String

    var imageURL: URL? {
        URL(string: self.imageUrl)
    }
}

/// Minimum identifying fields from the `cards` row. We only need the id
/// (for POST /api/study/answer) — keep the struct lean so decoding is
/// cheap even with hundreds of items.
struct StudyCard: Decodable, Hashable {
    let id: Int
    let cardType: String?
    let deckKey: String?
}

struct StudyQueueItem: Decodable, Hashable, Identifiable {
    let card: StudyCard
    let word: StudyQueueWord
    let choices: [String]?
    let spellingChoices: [String]?
    let mastery: Int?

    var id: String {
        self.word.id
    }
}

struct StudyQueueResponse: Decodable {
    let queue: [StudyQueueItem]
    let stats: StudyStats?
}

/// SRS rating accepted by POST /api/study/answer. Strings encode directly
/// in the JSON body — the backend maps them via VALID_RATINGS.
enum SRSRating: String, Codable {
    case again = "重來"
    case hard = "困難"
    case good = "穩定"
    case easy = "熟練"
}

// Marked `nonisolated` so the synthesized `Encodable` conformance is
// non-MainActor — APIClient.fireAndForget's `B: Encodable & Sendable`
// requires non-isolated conformance.
// swiftformat:disable:next redundantSendable
nonisolated struct StudyAnswerPayload: Encodable, Sendable {
    let cardId: Int
    let rating: String
    let responseMs: Int?
    let sessionId: String?
    let activity: String?

    init(
        cardId: Int,
        rating: SRSRating,
        responseMs: Int? = nil,
        sessionId: String? = nil,
        activity: String? = nil
    ) {
        self.cardId = cardId
        self.rating = rating.rawValue
        self.responseMs = responseMs
        self.sessionId = sessionId
        self.activity = activity
    }
}

struct StudyAnswerResponse: Decodable {
    let ok: Bool?
    let mastery: Int?
    let nextReview: String?
}
