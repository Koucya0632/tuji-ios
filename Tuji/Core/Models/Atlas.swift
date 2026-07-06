import Foundation

struct AtlasImageSummary: Decodable, Hashable, Identifiable {
    let id: String
    let status: String
    let width: Int?
    let height: Int?
    let createdAt: String?
    let updatedAt: String?
    let deletedAt: String?
    let imageUrl: String?
    let thumbUrl: String?

    var imageURL: URL? {
        self.imageUrl.flatMap(URL.init(string:))
    }

    var thumbURL: URL? {
        self.thumbUrl.flatMap(URL.init(string:))
    }
}

struct AtlasImagesResponse: Decodable {
    let images: [AtlasImageSummary]
}

struct AtlasUploadResponse: Decodable {
    let duplicate: Bool?
    let targetLanguage: String?
    let image: AtlasImageSummary
    let job: AtlasRecognitionJobSummary?
    /// Primary candidates now come back inline with the upload (recognition runs
    /// server-side in the same request) — nil/empty if recognition was skipped
    /// or failed, in which case the user retries via the AI 識別 button.
    let candidates: [AtlasCandidate]?
}

struct AtlasRecognitionJobSummary: Decodable, Hashable, Identifiable {
    let id: String
    let status: String
    let stage: String
    let provider: String?
    let model: String?
    let uncertaintyReason: String?
    let escalated: Bool?
    let createdAt: String?
    let updatedAt: String?
}

/// Recognition depth requested via POST /images/{id}/recognize. Raw values are
/// the wire strings the server expects (AI 識別 = primary, 高精度 = escalate).
enum AtlasRecognitionMode: String {
    case primary
    case escalate
}

/// Candidate granularity tier the server returns. `AtlasCandidate.level` stays
/// a raw String so an unknown future tier never fails decoding; compare
/// through `levelKind` instead of string literals.
enum AtlasCandidateLevel: String {
    case primary
    case fine
}

struct AtlasCandidate: Decodable, Hashable, Identifiable {
    let id: String
    let level: String
    let label: String
    let normalizedLabel: String
    let zhHant: String?
    let confidence: Double
    let rank: Int

    var levelKind: AtlasCandidateLevel? {
        AtlasCandidateLevel(rawValue: self.level)
    }

    private enum CodingKeys: String, CodingKey {
        case id, level, label, normalizedLabel, zhHant, confidence, rank
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(String.self, forKey: .id)
        self.level = try c.decode(String.self, forKey: .level)
        self.label = try c.decode(String.self, forKey: .label)
        self.normalizedLabel = try c.decode(String.self, forKey: .normalizedLabel)
        self.zhHant = try c.decodeIfPresent(String.self, forKey: .zhHant)
        // The recognize route returns the raw DB row, where `confidence`
        // (Postgres NUMERIC) serializes as a string — tolerate string-or-number.
        self.confidence = try c.decodeFlexibleDouble(forKey: .confidence)
        self.rank = try c.decode(Int.self, forKey: .rank)
    }
}

struct AtlasRecognitionResponse: Decodable {
    let job: AtlasRecognitionJobSummary?
    let candidates: [AtlasCandidate]
}

struct AtlasConfirmPayload: Codable {
    let selectedCandidateId: String?
    let targetLanguage: String?
    let primaryLabel: String
    let fineLabel: String?
    let lemma: String
    let displayZhHant: String
    let partOfSpeech: String?
    let category: String?
}

struct AtlasItem: Decodable, Hashable, Identifiable {
    let id: String
    let imageId: String
    let targetLanguage: String
    let canonicalWordId: String?
    let primaryLabel: String
    let fineLabel: String?
    let lemma: String
    let displayZhHant: String
    let partOfSpeech: String?
    let cefrLevel: String?
    let pronunciation: String?
    let reading: String?
    let category: String?
    let taxonomyPath: [String]?
    let definitionZhHant: String?
    let definitionTarget: String?
    let exampleTarget: String?
    let exampleZhHant: String?
    let noteZhHant: String?
    let visibility: String?
    let reviewStatus: String?
    let publicSlug: String?
    let createdAt: String?
    let updatedAt: String?
    let deletedAt: String?
}

struct AtlasItemResponse: Decodable {
    let item: AtlasItem
}

struct AtlasCardsPayload: Encodable {
    let cardTypes: [String]
}

struct AtlasCard: Decodable, Hashable, Identifiable {
    let id: String
    let itemId: String
    let imageId: String
    let deckKey: String
    let cardType: String
    let frontText: String?
    let back: String
    let explanation: String?
    let tags: [String]?
    let createdAt: String?
    let updatedAt: String?
    let deletedAt: String?
}

struct AtlasCardsResponse: Decodable {
    let cards: [AtlasCard]
}

struct AtlasCardState: Decodable, Hashable {
    let cardId: String
    let status: String
    let intervalDays: Double
    let nextReviewAt: String
    let reviewCount: Int
    let mistakeCount: Int
    let lastRating: String?
    let lastReviewedAt: String?
    let updatedAt: String?
}

struct AtlasMasteryEntry: Decodable, Hashable {
    let itemId: String
    let targetLanguage: String
    let mastery: Double
    let lastReviewedAt: String?
    let reviewCount: Int
    let updatedAt: String?
}

struct AtlasSyncResponse: Decodable {
    let serverTime: String
    let images: [AtlasImageSummary]
    let items: [AtlasItem]
    let cards: [AtlasCard]
    let cardStates: [AtlasCardState]
    let mastery: [AtlasMasteryEntry]
    let paging: AtlasSyncPaging
}

struct AtlasSyncPaging: Decodable, Hashable {
    let limit: Int
    let truncated: Bool
}

// MARK: - Entitlement / quota (GET /api/atlas/entitlement)

/// Free/Pro plan, its limits, and the user's current usage. Mirrors the server
/// (docs/ATLAS_PRICING_PLAN.md); used to gate capture UI and show remaining
/// quota. Ordinary AI is a per-tier monthly soft limit; precision (高精度) is
/// Pro-only (Free limit 0).
struct AtlasEntitlement: Decodable, Hashable {
    let plan: String
    let atlasSlotsLimit: Int
    let primaryAiSoftLimitMonthly: Int
    let precisionAiLimitMonthly: Int
    let subscriptionExpiresAt: String?
    let usage: AtlasUsage

    var isPro: Bool {
        self.plan == "pro"
    }
}

struct AtlasUsage: Decodable, Hashable {
    let atlasSlots: Int
    let primaryAiThisMonth: Int
    let precisionAiThisMonth: Int
}

private extension KeyedDecodingContainer {
    /// Decodes a Double that may arrive as a JSON number or a numeric string.
    /// A few atlas routes return raw Postgres NUMERIC columns (e.g. candidate
    /// `confidence`, study-state `interval_days`), which serialize as strings
    /// like "0.9500"; this tolerates both forms so decoding doesn't fail.
    func decodeFlexibleDouble(forKey key: Key) throws -> Double {
        if let value = try? decode(Double.self, forKey: key) { return value }
        let raw = try decode(String.self, forKey: key)
        guard let value = Double(raw) else {
            throw DecodingError.dataCorruptedError(
                forKey: key,
                in: self,
                debugDescription: "Expected Double or numeric string, got \"\(raw)\""
            )
        }
        return value
    }
}
