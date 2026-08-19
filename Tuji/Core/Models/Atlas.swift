// 自製圖鑑 — the wire model for a user's OWN atlas: capture → AI 識別 → 校正 →
// confirm, plus the cards, sync and entitlement that hang off it. Everything
// here is account-scoped and private to its owner.
//
// The community half (公開圖鑑, 合集, publish/review) lives in
// AtlasCommunity.swift. The split follows CONTEXT.md's domain line rather than
// file size: crossing from one file to the other is exactly the moderation
// gate, so "is this private or is this everyone's?" is answerable by which file
// a type is in.

import Foundation

/// Where an uploaded capture sits in the server's card-generation pipeline.
/// `AtlasImageSummary.status` stays a raw String on the wire so an unknown
/// future status never fails decoding; compare through `statusKind`, never
/// against string literals.
enum AtlasImageStatus: String, Hashable, CaseIterable {
    case uploaded
    case processing
    case needsReview = "needs_review"
    case confirmed
    case cardsReady = "cards_ready"
    case failed
    case deleted

    var label: String {
        switch self {
        case .uploaded: tujiLocalized("已上傳")
        case .processing: tujiLocalized("生成中")
        case .needsReview: tujiLocalized("待確認")
        case .confirmed: tujiLocalized("已確認")
        case .cardsReady: tujiLocalized("已完成")
        case .failed: tujiLocalized("生成失敗")
        case .deleted: tujiLocalized("已刪除")
        }
    }

    /// True once the pipeline has produced the confirmed item behind the image.
    /// A row in one of these states with no joined item is a *sync* gap, not an
    /// unfinished capture — the distinction the old fixed 未完成 fallback lost.
    var impliesConfirmedItem: Bool {
        switch self {
        case .confirmed, .cardsReady: true
        case .uploaded, .processing, .needsReview, .failed, .deleted: false
        }
    }
}

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

    /// Parsed `status`; nil for a value this build doesn't know about.
    var statusKind: AtlasImageStatus? {
        AtlasImageStatus(rawValue: self.status)
    }

    /// User-facing pipeline status. An unrecognised value falls through raw so a
    /// new backend status is at least visible rather than silently blank.
    var statusLabel: String {
        self.statusKind?.label ?? self.status
    }

    /// Row title when no confirmed item has joined this image yet. Derived from
    /// the status so it can never contradict the status shown beside it — the
    /// old fixed 未完成 sat next to 已完成 whenever a truncated sync dropped the
    /// item.
    var placeholderTitle: String {
        guard let kind = self.statusKind else { return tujiLocalized("未完成") }
        return kind.impliesConfirmedItem ? tujiLocalized("尚未同步") : kind.label
    }
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

/// `Equatable` so `CaptureJobRecord` — which carries one across an app kill —
/// can be compared in a test without unpacking nine fields.
struct AtlasConfirmPayload: Codable, Equatable {
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

/// What `AtlasStore.merge` actually reads, and nothing else.
///
/// The payload also carries `cards`, `cardStates`, `mastery` and `paging`, and
/// this struct used to decode all four — strictly, non-optionally — into
/// properties no screen ever read. `AtlasCardState` and `AtlasMasteryEntry`
/// existed for that and were referenced nowhere else in the app or its tests.
///
/// The cost was not the wasted work. `cardStates.intervalDays` is a Postgres
/// NUMERIC, so it arrives as `"1.0000"`; one such value, or one missing key on
/// a partial deploy, threw — and `APIClient` turns a decode failure into
/// **資料解析失敗** across the whole 圖鑑管理 shelf. A field nothing reads could
/// blank a screen.
///
/// Same rule ADR-0001 applied to `publicFeed`: what has no caller goes.
struct AtlasSyncResponse: Decodable {
    let serverTime: String
    let images: [AtlasImageSummary]
    @LossyArray var items: [AtlasItem]
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
