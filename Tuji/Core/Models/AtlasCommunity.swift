// 公開圖鑑 / 合集 — the community half of the atlas wire model.
//
// Split from Atlas.swift, which keeps the 自製圖鑑 side (capture → 識別 → 確認,
// cards, sync, entitlement). The line between them is the one CONTEXT.md draws:
// these types describe work that has passed the moderation gate and belongs to
// everyone, so none of them carries private user data. `AtlasReviewStatus` and
// the publish/withdraw responses live here too — they describe the crossing.

import Foundation

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
    /// The public identity attached to the share. Nil is reserved for rows whose
    /// author account is no longer available.
    let author: AtlasAuthorRef?
    let publishedAt: String?
    /// Full stored learning content. Feed and collection-preview payloads omit
    /// it; the single-item detail endpoint supplies it without invoking AI.
    var learningWord: Word?
    /// Present only on owner collection endpoints. Public feeds omit them.
    var publicItemId: String? = nil
    var reviewStatus: String? = nil
    var publicationState: String? = nil
    var eligible: Bool? = nil

    var imageURL: URL? {
        self.imageUrl.flatMap(URL.init(string:))
    }

    var langBadge: String {
        self.targetLanguage.rawValue.uppercased()
    }

    var collectionPublicationLabel: String? {
        switch self.publicationState {
        case "private": tujiLocalized("將隨合集送審")
        case "pending": tujiLocalized("審核中")
        default: nil
        }
    }
}

/// GET /api/atlas/public/by-lemma — everyone else's public items for one word.
struct AtlasPublicByLemmaResponse: Decodable {
    let lemma: String
    let targetLanguage: TargetLanguage
    @LossyArray var items: [AtlasPublicItem]
}

/// GET /api/atlas/public — the community wall.
struct AtlasPublicFeedResponse: Decodable {
    @LossyArray var items: [AtlasPublicItem]
}

/// GET /api/atlas/public/{slug} — one public item.
struct AtlasPublicItemResponse: Decodable {
    let item: AtlasPublicItem
}

/// A community author's public identity and aggregate impact.
struct AtlasAuthor: Decodable, Identifiable, Hashable {
    /// Link target for the author route. Distinct from `displayName`: the
    /// handle is unique and URL-safe, the name is neither.
    let handle: String
    let displayName: String
    /// Avatar pose key from `profiles.avatar`.
    let avatar: String
    /// Author-written self-introduction, text-gated on write. Optional so a
    /// payload from a server predating the field still decodes; empty is the
    /// same as absent for rendering purposes.
    let bio: String?
    let joinedAt: String?
    let publishedCount: Int
    /// How many times this author's items have been saved by others — the
    /// altruistic feedback signal (../docs/COMMUNITY_ATLAS_PLAN.md §3C —
    /// FEATURES.md §12.5).
    let saveCount: Int

    var id: String {
        self.handle
    }
}

/// GET /api/atlas/public/authors/{username}
struct AtlasAuthorResponse: Decodable, Hashable {
    let author: AtlasAuthor
    @LossyArray var items: [AtlasPublicItem]
    /// The author's approved 合集. Defaulted rather than required: this key was
    /// added after 1.0.4 shipped, so a build carrying it can meet a server that
    /// predates it (and the reverse — older clients simply ignore the key). An
    /// author page must not fail to decode over a deploy-ordering accident.
    @LossyArray var collections: [AtlasCollection]

    init(author: AtlasAuthor, items: [AtlasPublicItem], collections: [AtlasCollection] = []) {
        self.author = author
        self.items = items
        self.collections = collections
    }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.author = try c.decode(AtlasAuthor.self, forKey: .author)
        self.items = try c.decodeIfPresent([AtlasPublicItem].self, forKey: .items) ?? []
        self.collections = try c.decodeIfPresent([AtlasCollection].self, forKey: .collections) ?? []
    }

    private enum CodingKeys: String, CodingKey {
        case author, items, collections
    }
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
/// server's `review_status` (../docs/COMMUNITY_ATLAS_PLAN.md §5 —
/// FEATURES.md §12.7): submitting runs
/// a machine gate that either publishes immediately, routes to a human, or
/// rejects. `pending` is the legacy single queue kept for older rows.
enum AtlasReviewStatus: String, Decodable, Hashable {
    case draft
    case pending
    case pendingAuto = "pending_auto"
    case pendingReview = "pending_review"
    case approved
    case rejected
    /// Moderation removed it. Final — the server refuses to re-submit it.
    case takedown
    /// The author took it down themselves. Reversible, and carries no penalty.
    case withdrawn

    /// Short label for the detail screen. Deliberately says 送審/審核 — approval
    /// is not automatic, so the UI must never imply "already public".
    var label: String {
        switch self {
        case .draft: tujiLocalized("未公開")
        case .pending, .pendingAuto, .pendingReview: tujiLocalized("審核中")
        case .approved: tujiLocalized("已公開")
        case .rejected: tujiLocalized("未通過")
        case .takedown: tujiLocalized("已下架")
        case .withdrawn: tujiLocalized("已收回")
        }
    }

    /// Only these states offer the submit action; anything in-flight or already
    /// public must not be re-submitted. `withdrawn` is submittable precisely
    /// because it was the author's own decision — unlike `takedown`.
    var canSubmit: Bool {
        switch self {
        case .draft, .rejected, .withdrawn: true
        case .pending, .pendingAuto, .pendingReview, .approved, .takedown: false
        }
    }

    /// Only a live public item can be pulled back. Withdrawal is not a way to
    /// escape a moderation takedown, and there is nothing to withdraw from a
    /// draft or a queued submission.
    var canWithdraw: Bool {
        self == .approved
    }
}

extension AtlasItem {
    /// Parsed `reviewStatus`, defaulting to `.draft` for items that predate the
    /// field or arrive without it.
    var review: AtlasReviewStatus {
        AtlasReviewStatus(rawValue: self.reviewStatus ?? "") ?? .draft
    }
}

/// POST /api/atlas/items/{id}/withdraw. The server owns the resulting state;
/// the client re-syncs rather than guessing it.
struct AtlasWithdrawResponse: Decodable, Hashable {
    let ok: Bool
    let reviewStatus: String?
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
    /// The public identity attached to the collection.
    let author: AtlasAuthorRef?
    let itemCount: Int
    let saveCount: Int
    let avatarColor: String?
    let avatarImageUrl: String?
    let coverImageUrl: String?
    let publishedAt: String?

    var coverURL: URL? {
        self.coverImageUrl.flatMap(URL.init(string:))
    }

    var avatarURL: URL? {
        self.avatarImageUrl.flatMap(URL.init(string:))
    }

    var langBadge: String {
        self.targetLanguage.rawValue.uppercased()
    }

    func withSaveCount(_ saveCount: Int) -> AtlasCollection {
        AtlasCollection(
            id: self.id,
            slug: self.slug,
            title: self.title,
            description: self.description,
            targetLanguage: self.targetLanguage,
            author: self.author,
            itemCount: self.itemCount,
            saveCount: saveCount,
            avatarColor: self.avatarColor,
            avatarImageUrl: self.avatarImageUrl,
            coverImageUrl: self.coverImageUrl,
            publishedAt: self.publishedAt
        )
    }

    func withAuthor(_ author: AtlasAuthorRef?) -> AtlasCollection {
        AtlasCollection(
            id: self.id,
            slug: self.slug,
            title: self.title,
            description: self.description,
            targetLanguage: self.targetLanguage,
            author: author,
            itemCount: self.itemCount,
            saveCount: self.saveCount,
            avatarColor: self.avatarColor,
            avatarImageUrl: self.avatarImageUrl,
            coverImageUrl: self.coverImageUrl,
            publishedAt: self.publishedAt
        )
    }

    /// The 簡介 as something to render, or nil when there is none.
    ///
    /// Three places asked this and two of them trimmed first: the create and
    /// edit models nil a whitespace-only description before sending, and the
    /// detail view read `description.flatMap { $0.isEmpty ? nil : $0 }` — no
    /// trim. So a row whose 簡介 is three spaces (an older row, or one written
    /// by the web client) rendered as *present*, in the has-content ink rather
    /// than the placeholder grey, showing nothing.
    var blurb: String? {
        guard let description else { return nil }
        let trimmed = description.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

/// GET /api/atlas/public/collections
struct AtlasPublicCollectionsResponse: Decodable {
    @LossyArray var collections: [AtlasCollection]
}

/// GET /api/atlas/public/collections/{slug}
struct AtlasCollectionDetailResponse: Decodable {
    let collection: AtlasCollection
    @LossyArray var items: [AtlasPublicItem]
    var access: AtlasCollectionAccess?
}

struct AtlasCollectionAccess: Decodable, Equatable {
    let unlocked: Bool
    let isOwner: Bool
    let isSaved: Bool
    let totalCount: Int
    let learningCount: Int
}

struct AtlasCollectionLearnResponse: Decodable, Equatable {
    let ok: Bool
    let addedCount: Int
    let learningCount: Int
    let totalCount: Int
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
    let avatarColor: String?
    let avatarImageUrl: String?
    let coverImageUrl: String?
    let publishedAt: String?
    let updatedAt: String?

    var coverURL: URL? {
        self.coverImageUrl.flatMap(URL.init(string:))
    }

    var avatarURL: URL? {
        self.avatarImageUrl.flatMap(URL.init(string:))
    }

    var review: AtlasReviewStatus {
        AtlasReviewStatus(rawValue: self.reviewStatus) ?? .draft
    }
}

/// GET /api/atlas/collections  and the body of POST create.
struct AtlasMyCollectionsResponse: Decodable {
    @LossyArray var collections: [AtlasMyCollection]
}

struct AtlasMyCollectionResponse: Decodable {
    let collection: AtlasMyCollection
}

/// GET /api/atlas/collections/{id} — the owner edit view (collection + members).
struct AtlasCollectionEditResponse: Decodable {
    let collection: AtlasCollectionEdit
    @LossyArray var items: [AtlasPublicItem]
}

struct AtlasCollectionEdit: Decodable, Hashable {
    let id: String
    let slug: String
    let title: String
    let description: String?
    let targetLanguage: TargetLanguage
    let reviewStatus: String
    let avatarColor: String?
    let avatarPreviewUrl: String?
    let coverPublicItemId: String?
    let coverImageUrl: String?
    let publishedAt: String?
    let updatedAt: String?

    var review: AtlasReviewStatus {
        AtlasReviewStatus(rawValue: self.reviewStatus) ?? .draft
    }

    var avatarPreviewURL: URL? {
        self.avatarPreviewUrl.flatMap(URL.init(string:))
    }
}

/// POST /api/atlas/collections/{id}/avatar — the public collection avatar and
/// its fallback color are committed as one change.
struct AtlasCollectionAvatarResponse: Decodable, Equatable {
    let ok: Bool
    let avatarColor: String
    let avatarImageUrl: String
    let avatarPreviewUrl: String?
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
    let sourceItemId: String
}
