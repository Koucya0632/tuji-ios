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
    let targetLanguage: TargetLanguage?
    let image: AtlasImageSummary
    let job: AtlasRecognitionJobSummary?
    /// Primary candidates now come back inline with the upload (recognition runs
    /// server-side in the same request) — nil/empty if recognition was skipped
    /// or failed, in which case the user retries via the 普通識別 button.
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
    /// Gloss in the user's UI language (ja/en interfaces only; nil otherwise).
    let gloss: String?
    let confidence: Double
    let rank: Int

    var levelKind: AtlasCandidateLevel? {
        AtlasCandidateLevel(rawValue: self.level)
    }

    private enum CodingKeys: String, CodingKey {
        case id, level, label, normalizedLabel, zhHant, gloss, confidence, rank
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(String.self, forKey: .id)
        self.level = try c.decode(String.self, forKey: .level)
        self.label = try c.decode(String.self, forKey: .label)
        self.normalizedLabel = try c.decode(String.self, forKey: .normalizedLabel)
        self.zhHant = try c.decodeIfPresent(String.self, forKey: .zhHant)
        self.gloss = try c.decodeIfPresent(String.self, forKey: .gloss)
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
    let targetLanguage: TargetLanguage?
    let primaryLabel: String
    let fineLabel: String?
    let lemma: String
    let displayZhHant: String
    /// The gloss field's value in the user's UI language (ja/en); the server
    /// routes it to display_ja/display_en. nil for Chinese UIs.
    let displayGloss: String?
    let partOfSpeech: String?
    let category: String?
}

struct AtlasItem: Decodable, Hashable, Identifiable {
    let id: String
    let imageId: String
    let targetLanguage: TargetLanguage
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

// MARK: - Public 圖鑑 (community)

/// One approved, publicly shared 圖鑑 item by any user. Served by
/// `/api/atlas/public*`; contains no private user data.
struct AtlasPublicItem: Decodable, Identifiable, Hashable {
    let id: String
    let slug: String
    let lemma: String
    let displayZhHant: String
    let targetLanguage: TargetLanguage
    let category: String?
    let imageUrl: String?
    /// The author, or nil when they never accepted a public identity. Anonymous
    /// is a real state, not a missing value: the server refuses to name someone
    /// who has not agreed to be named, so the UI must render the nil case
    /// rather than substituting a handle.
    let author: AtlasAuthorRef?
    let publishedAt: String?

    var imageURL: URL? {
        self.imageUrl.flatMap(URL.init(string:))
    }

    var langBadge: String {
        self.targetLanguage.rawValue.uppercased()
    }
}

/// GET /api/atlas/public/by-lemma — everyone else's public items for one word.
struct AtlasPublicByLemmaResponse: Decodable {
    let lemma: String
    let targetLanguage: TargetLanguage
    let items: [AtlasPublicItem]
}

/// GET /api/atlas/public — the community wall.
struct AtlasPublicFeedResponse: Decodable {
    let items: [AtlasPublicItem]
}

/// A community author's public identity and aggregate impact.
struct AtlasAuthor: Decodable, Identifiable, Hashable {
    /// Link target for the author route. Distinct from `displayName`: the
    /// handle is unique and URL-safe, the name is neither.
    let handle: String
    let displayName: String
    /// Avatar pose key from `profiles.avatar`.
    let avatar: String
    let joinedAt: String?
    let publishedCount: Int
    /// How many times this author's items have been saved by others — the
    /// altruistic feedback signal (docs/COMMUNITY_ATLAS_PLAN.md §3C).
    let saveCount: Int

    var id: String {
        self.handle
    }
}

/// GET /api/atlas/public/authors/{username}
struct AtlasAuthorResponse: Decodable, Hashable {
    let author: AtlasAuthor
    let items: [AtlasPublicItem]
}

/// POST/DELETE /api/atlas/public/{slug}/save
struct AtlasSaveResponse: Decodable, Hashable {
    let ok: Bool
    let saved: Bool
    let saveCount: Int
}

/// POST /api/atlas/public/{slug}/report
enum AtlasReportReason: String, CaseIterable, Identifiable {
    case spam
    case inappropriate
    case copyright
    case wrong
    case other

    var id: String {
        self.rawValue
    }

    var label: String {
        switch self {
        case .spam: tujiLocalized("垃圾內容")
        case .inappropriate: tujiLocalized("不當內容")
        case .copyright: tujiLocalized("侵犯版權")
        case .wrong: tujiLocalized("內容有誤")
        case .other: tujiLocalized("其他")
        }
    }
}

struct AtlasReportPayload: Encodable {
    let reason: String
    let detail: String?
}

// MARK: - Publish / review (POST /api/atlas/items/{id}/publish)

/// Where a 自製圖鑑 item sits in the public-review pipeline. Mirrors the
/// server's `review_status` (docs/COMMUNITY_ATLAS_PLAN.md §5): submitting runs
/// a machine gate that either publishes immediately, routes to a human, or
/// rejects. `pending` is the legacy single queue kept for older rows.
enum AtlasReviewStatus: String, Decodable, Hashable {
    case draft
    case pending
    case pendingAuto = "pending_auto"
    case pendingReview = "pending_review"
    case approved
    case rejected
    case takedown

    /// Short label for the detail screen. Deliberately says 送審/審核 — approval
    /// is not automatic, so the UI must never imply "already public".
    var label: String {
        switch self {
        case .draft: tujiLocalized("未公開")
        case .pending, .pendingAuto, .pendingReview: tujiLocalized("審核中")
        case .approved: tujiLocalized("已公開")
        case .rejected: tujiLocalized("未通過")
        case .takedown: tujiLocalized("已下架")
        }
    }

    /// Only these states offer the submit action; anything in-flight or already
    /// public must not be re-submitted.
    var canSubmit: Bool {
        switch self {
        case .draft, .rejected: true
        case .pending, .pendingAuto, .pendingReview, .approved, .takedown: false
        }
    }
}

extension AtlasItem {
    /// Parsed `reviewStatus`, defaulting to `.draft` for items that predate the
    /// field or arrive without it.
    var review: AtlasReviewStatus {
        AtlasReviewStatus(rawValue: self.reviewStatus ?? "") ?? .draft
    }
}

/// Server's answer to a submit. `moderation.published` is true only when the
/// machine gate cleared it outright.
struct AtlasPublishResponse: Decodable {
    let item: AtlasItem
    let moderation: AtlasPublishModeration?
}

struct AtlasPublishModeration: Decodable, Hashable {
    let reviewStatus: String
    let published: Bool

    var status: AtlasReviewStatus {
        AtlasReviewStatus(rawValue: self.reviewStatus) ?? .pendingReview
    }
}

// MARK: - Community collections 合集

/// Minimal author identity carried on a public item or collection card. The
/// browse card shows the collection's own counts, not the author's totals, so
/// this is deliberately smaller than `AtlasAuthor`.
struct AtlasAuthorRef: Decodable, Hashable {
    /// Link target for the author route — never shown as a name.
    let handle: String
    let displayName: String
    let avatar: String
}

/// A public collection: browse-card meta, and the header of the detail page.
struct AtlasCollection: Decodable, Identifiable, Hashable {
    let id: String
    let slug: String
    let title: String
    let description: String?
    let targetLanguage: TargetLanguage
    /// nil when the author has no confirmed public identity — same rule as
    /// `AtlasPublicItem.author`.
    let author: AtlasAuthorRef?
    let itemCount: Int
    let saveCount: Int
    let coverImageUrl: String?
    let publishedAt: String?

    var coverURL: URL? {
        self.coverImageUrl.flatMap(URL.init(string:))
    }

    var langBadge: String {
        self.targetLanguage.rawValue.uppercased()
    }
}

/// GET /api/atlas/public/collections
struct AtlasPublicCollectionsResponse: Decodable {
    let collections: [AtlasCollection]
}

/// GET /api/atlas/public/collections/{slug}
struct AtlasCollectionDetailResponse: Decodable {
    let collection: AtlasCollection
    let items: [AtlasPublicItem]
}

/// One of the current user's own collections (all review states) — 我的合集 list.
struct AtlasMyCollection: Decodable, Identifiable, Hashable {
    let id: String
    let slug: String
    let title: String
    let description: String?
    let targetLanguage: TargetLanguage
    let reviewStatus: String
    let itemCount: Int
    let coverImageUrl: String?
    let publishedAt: String?
    let updatedAt: String?

    var coverURL: URL? {
        self.coverImageUrl.flatMap(URL.init(string:))
    }

    var review: AtlasReviewStatus {
        AtlasReviewStatus(rawValue: self.reviewStatus) ?? .draft
    }
}

/// GET /api/atlas/collections  and the body of POST create.
struct AtlasMyCollectionsResponse: Decodable {
    let collections: [AtlasMyCollection]
}

struct AtlasMyCollectionResponse: Decodable {
    let collection: AtlasMyCollection
}

/// GET /api/atlas/collections/{id} — the owner edit view (collection + members).
struct AtlasCollectionEditResponse: Decodable {
    let collection: AtlasCollectionEdit
    let items: [AtlasPublicItem]
}

struct AtlasCollectionEdit: Decodable, Hashable {
    let id: String
    let slug: String
    let title: String
    let description: String?
    let targetLanguage: TargetLanguage
    let reviewStatus: String
    let coverPublicItemId: String?
    let coverImageUrl: String?
    let publishedAt: String?
    let updatedAt: String?

    var review: AtlasReviewStatus {
        AtlasReviewStatus(rawValue: self.reviewStatus) ?? .draft
    }
}

/// POST /api/atlas/collections/{id}/publish
struct AtlasCollectionPublishResponse: Decodable {
    let moderation: AtlasPublishModeration?
}

struct AtlasCollectionCreatePayload: Encodable {
    let title: String
    let description: String?
    let targetLanguage: String
}

struct AtlasCollectionUpdatePayload: Encodable {
    let title: String
    let description: String?
    let coverPublicItemId: String?
}

struct AtlasCollectionAddItemPayload: Encodable {
    let publicItemId: String
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
    let targetLanguage: TargetLanguage
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
