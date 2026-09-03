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
    /// The 釋義 — the explanatory sentence the detail page prints under the
    /// headline, in the reader's own language. 複習's 求救提示 turns the picture
    /// over to this rather than to `chinese`, which for a zh reader is the
    /// answer translated (水桶) rather than a hint.
    ///
    /// Optional twice over: the catalogue does not have one for every word, and
    /// the server deliberately withholds it when it would only repeat the gloss
    /// (lib/study-hint.ts) — the case where the gloss *is* the definition,
    /// written in the language being tested. So `nil` is the ordinary state,
    /// not a decoding failure, and the hint falls back to the gloss.
    let definition: String?

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

/// One authored example sentence, with everything 聽句 needs to ask about it.
///
/// Attached to the queue item rather than fetched per card: the question has to
/// be ready the moment the card appears, and a hundred-item queue cannot pay a
/// detail round-trip each. What is deliberately *not* here is `spans` — the
/// tappable version of this sentence is one pull-up away in the reveal sheet
/// (`WordDetailSheet` fetches it on demand), so carrying the annotation for
/// every card would ship a hundred copies to serve the one the user opens.
struct StudyExample: Decodable, Hashable {
    /// The sentence in the language being learned. Rendered blurred, and never
    /// through `InteractiveSentenceText` — without spans there is nothing to
    /// tap, and a live-looking sentence that is dead is worse than a plain one.
    let sentence: String
    /// `A2` (the simpler of the authored pair) or `B1` (the harder). Every
    /// published word has exactly one of each; `ListeningQuestion` picks
    /// between them by mastery.
    let cefrLevel: String?
    /// Pre-generated clips keyed by locale, same shape as a word's. Nil when
    /// the sentence has no recording yet — such a card simply is not asked as
    /// 聽句, because the on-device fallback would be reading kanji by a guess
    /// the app cannot correct.
    let audioUrls: [String: String]?
    /// Every catalogue word this sentence names, the target included. The
    /// image distractor must avoid all of them: 46% of the English sentences
    /// name two catalogue nouns, and drawing the other one makes both pictures
    /// correct. Resolved server-side from the sentence's own 詞塊, which is the
    /// only place the base-form → word id mapping exists.
    let mentionedWordIds: [String]?
}

struct StudyQueueItem: Decodable, Hashable, Identifiable {
    let card: StudyCard
    let word: StudyQueueWord
    let choices: [String]?
    let spellingChoices: [String]?
    let mastery: Int?
    /// The word's authored example pair. Absent for 自製圖鑑 and 物見 cards,
    /// which have no example sentences at all — the reason 聽句 needs a
    /// fallback question rather than a gate at the session's entrance.
    let examples: [StudyExample]?

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
    /// The user turned the picture over before answering (複習's 求救提示).
    /// What they read there is the 釋義 or the gloss depending on the word; what
    /// this records is that they asked, which is the part the rating cares
    /// about (ADR-0007). Optional
    /// so answers parked on disk by an older build still decode — a new
    /// non-optional key would fail every one of them.
    let hinted: Bool?
    /// 聽句 only: how many times the sentence was replayed before answering.
    /// Lands in `study_logs.metadata` for the same reason `hinted` does —
    /// the table is append-only, so a signal not written now is unrecoverable —
    /// and by the same mechanism, because `activity` has a closed enum at both
    /// ends while `metadata` has no constraint and needs no migration.
    let replayCount: Int?
    /// 聽句 only: the clip was missing or unreachable and the sentence was read
    /// by on-device synthesis instead. That answer is not evidence about
    /// listening in either direction, so the analysis has to be able to drop it.
    let audioFailed: Bool?
    /// 這輪不做聽句題 was on when this was answered.
    ///
    /// Sent on **every** activity, not just 聽句 — that is the point. A session
    /// with listening turned off answers the rest of its cards as 選字, and
    /// without this flag those rows are indistinguishable from a session that
    /// never had a listening question to begin with. That difference is exactly
    /// what makes an aggregate listening accuracy honest or not.
    let listeningOptedOut: Bool?
    /// This card was a 聽句 question until the user turned listening off on it.
    ///
    /// Its `activity` now says `mcq`, truthfully — that is what was answered.
    /// But the card the user *bailed on* is the sharpest datum here, and it is
    /// the one place the fact is otherwise unrecoverable.
    let convertedFromListening: Bool?

    init(
        cardId: String,
        rating: SRSRating,
        responseMs: Int? = nil,
        sessionId: String? = nil,
        activity: String? = nil,
        ownerUserId: UUID? = nil,
        hinted: Bool? = nil,
        replayCount: Int? = nil,
        audioFailed: Bool? = nil,
        listeningOptedOut: Bool? = nil,
        convertedFromListening: Bool? = nil
    ) {
        self.cardId = cardId
        self.rating = rating.rawValue
        self.responseMs = responseMs
        self.sessionId = sessionId
        self.activity = activity
        self.ownerUserId = ownerUserId
        self.hinted = hinted
        self.replayCount = replayCount
        self.audioFailed = audioFailed
        self.listeningOptedOut = listeningOptedOut
        self.convertedFromListening = convertedFromListening
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
