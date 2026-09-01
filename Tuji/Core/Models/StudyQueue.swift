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
    let readingSegments: [FuriganaSegment]?
    let targetLanguage: TargetLanguage?
    let category: String

    var imageURL: URL? {
        URL(string: self.imageUrl)
    }

    var imageKind: WordImageKind {
        WordImageKind(category: self.category)
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

    /// What picking this actually means, in one line.
    ///
    /// The redesign asked for "next seen in 10 minutes / 1 day / 3 days" here,
    /// to turn each level into a comprehensible trade. The client cannot know
    /// those numbers — an interval only comes back in the *response* to
    /// POST /api/study/answer, after the rating is already sent — and printing
    /// invented ones would be a promise the app has no way to keep. So the line
    /// describes the state rather than promising a time, which needs no
    /// knowledge of the schedule to be true.
    var explanation: LocalizedStringKey {
        switch self {
        case .again: "還沒記住，再學一次"
        case .hard: "有印象，但要再看幾次"
        case .good: "記得，正常間隔"
        case .easy: "很有把握，拉長間隔"
        }
    }

    /// The 3pt leading edge. Ordered as a ladder from alert through 瞳黃 to the
    /// two teal steps — teal means accumulation, so the further right on the
    /// confidence scale, the deeper the teal.
    var edge: Color {
        switch self {
        case .again: .tujiAlert
        case .hard: .tujiCurrent
        case .good: .tujiAccumulationSoft
        case .easy: .tujiAccumulation
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
    /// Present for durable replays so the server can reject a request if the
    /// access token changed accounts while the replay was in flight.
    var ownerUserId: UUID?
    /// The user asked for the gloss before answering (複習's 求救提示). Optional
    /// so answers parked on disk by an older build still decode — a new
    /// non-optional key would fail every one of them.
    let hinted: Bool?

    init(
        cardId: String,
        rating: SRSRating,
        responseMs: Int? = nil,
        sessionId: String? = nil,
        activity: String? = nil,
        ownerUserId: UUID? = nil,
        hinted: Bool? = nil
    ) {
        self.cardId = cardId
        self.rating = rating.rawValue
        self.responseMs = responseMs
        self.sessionId = sessionId
        self.activity = activity
        self.ownerUserId = ownerUserId
        self.hinted = hinted
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
