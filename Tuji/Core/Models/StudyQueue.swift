// Models for the study session — queue items, ratings, answer payloads.
// Maps directly to `DueCard` on the backend (lib/cards-db.ts) and the
// /api/study/answer body.

import SwiftUI

/// Lightweight word payload embedded in the queue item. Fields match the
/// snake_case backend → camelCase decoder rewrite.
struct StudyQueueWord: Decodable, Hashable, Identifiable {
    let id: String
    let word: String
    let chinese: String
    let imageUrl: String
    let pronunciation: String
    let reading: String?
    let targetLanguage: TargetLanguage?
    let category: String

    var imageURL: URL? {
        URL(string: self.imageUrl)
    }
}

/// Minimum identifying fields from the `cards` row. We only need the id
/// (for POST /api/study/answer) — keep the struct lean so decoding is
/// cheap even with hundreds of items.
struct StudyCard: Decodable, Hashable {
    let id: String
    let cardType: String?
    let deckKey: String?

    private enum CodingKeys: String, CodingKey {
        case id
        case cardType
        case deckKey
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let intId = try? c.decode(Int.self, forKey: .id) {
            self.id = String(intId)
        } else {
            self.id = try c.decode(String.self, forKey: .id)
        }
        self.cardType = try c.decodeIfPresent(String.self, forKey: .cardType)
        self.deckKey = try c.decodeIfPresent(String.self, forKey: .deckKey)
    }
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

    /// User-facing label. The `rawValue` doubles as the wire value, so UI renders
    /// this `LocalizedStringKey` accessor instead of `rawValue` — it resolves
    /// against the SwiftUI environment locale and follows the uiLang toggle.
    var label: LocalizedStringKey {
        switch self {
        case .again: "重來"
        case .hard: "困難"
        case .good: "穩定"
        case .easy: "熟練"
        }
    }
}

// Marked `nonisolated` so the synthesized `Codable` conformance is
// non-MainActor — APIClient.fireAndForget's `B: Encodable & Sendable`
// requires non-isolated conformance. Decodable too so the offline outbox
// (StudyAnswerOutbox) can round-trip unsent answers through disk.
// swiftformat:disable:next redundantSendable
nonisolated struct StudyAnswerPayload: Codable, Sendable {
    let cardId: String
    let rating: String
    let responseMs: Int?
    let sessionId: String?
    let activity: String?

    init(
        cardId: String,
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

// Server emits `mastery: { before, after, delta, level }` and
// `next: { status, intervalDays, nextReviewAt, humanized, penaltyApplied }`
// — both nested objects. We model `milestone` (streak celebration) and the
// numeric `mastery` change (CompleteView's per-word 變化 list). The server's
// `mastery.level` object is intentionally *not* decoded: iOS derives its own
// 5-level MasteryLevel from the numbers. Codable skips undeclared keys, so the
// richer server payload still round-trips cleanly.
struct StudyAnswerResponse: Decodable {
    let ok: Bool?
    let milestone: Milestone?
    let mastery: MasteryDelta?
}

/// Word-level mastery before/after one answer (decayed `before`, blended
/// `after`). Drives the completion summary's per-word change rows.
struct MasteryDelta: Decodable, Hashable {
    let before: Int
    let after: Int
    let delta: Int
}

/// Server-attached signal that this answer triggered a streak milestone
/// (30 / 100 / 365 days). Currently decoded but not emitted by the
/// backend — wiring it iOS-side now means W5 server work can flip the
/// switch without a client release.
struct Milestone: Decodable, Hashable {
    let streak: Int
}
