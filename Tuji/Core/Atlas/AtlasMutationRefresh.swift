// One policy home for "what a 圖鑑管理 mutation refreshes, and when".
//
// The rule used to be restated at seven producers: the three-store fan-out was
// written verbatim in both the manage screen and the capture queue, and the
// public-feed invalidation was spelled out in five view bodies that already
// disagreed with each other (deleting a 合集 checked whether it was public;
// changing its avatar didn't). Deleting cards refreshed neither the entitlement
// it had just freed a slot in, so 「自製圖鑑已達上限」 outlived the deletion.
//
// Producers now state what the user did; this module owns the consequences.
// Mirrors CommunityLearningRefresh (the consumption side) and SessionRefresh
// (the study side) — this is the authoring side.

import Foundation

/// A completed 圖鑑管理 mutation, named by what the user did rather than by
/// which stores it happens to touch.
enum AtlasMutation: Hashable {
    /// 自製圖鑑 cards were deleted. Frees an atlas slot, so the entitlement that
    /// gates capture goes stale in the same moment.
    case itemsDeleted
    /// A capture finished generating its cards. Consumes an atlas slot.
    case captureCompleted
    /// 取消公開 on a single item. The item, its cards and every saver's progress
    /// stay — only the public row is retired.
    case itemWithdrawn
    /// A 合集 was submitted for review.
    case collectionPublished
    /// 取消公開 on a 合集.
    case collectionWithdrawn
    /// A 合集 was deleted. Only reaches the public wall if it was on it.
    case collectionDeleted(wasPublic: Bool)
    /// A 合集's public avatar changed. Same condition — a draft 合集 isn't on the
    /// wall, so re-fetching it past the cache buys nothing.
    case collectionAvatarChanged(isPublic: Bool)

    /// Whether the user's own 自製圖鑑 changed: the 圖鑑 grid (atlas items surface
    /// there as custom words), the home counters, the study stats, and the quota
    /// snapshot that gates capture.
    var changesOwnAtlas: Bool {
        switch self {
        case .itemsDeleted, .captureCompleted: true
        case .itemWithdrawn, .collectionPublished, .collectionWithdrawn,
             .collectionDeleted, .collectionAvatarChanged: false
        }
    }

    /// Whether 公開圖鑑's cached list can no longer be trusted.
    var invalidatesPublicFeed: Bool {
        switch self {
        case .itemWithdrawn, .collectionPublished, .collectionWithdrawn: true
        case let .collectionDeleted(wasPublic): wasPublic
        case let .collectionAvatarChanged(isPublic): isPublic
        case .itemsDeleted, .captureCompleted: false
        }
    }
}

@MainActor
protocol AtlasMutationRefreshing {
    func refresh(after mutation: AtlasMutation) async
}

/// Stateless live adapter. It deliberately has no lifecycle of its own; only
/// this module knows which app stores implement the policy.
@MainActor
struct LiveAtlasMutationRefresher: AtlasMutationRefreshing {
    private let reloadLearningStores: @MainActor () async -> Void
    private let refreshCapacity: @MainActor () async -> Void
    private let markFeedStale: @MainActor () -> Void

    /// `feed` defaults to nil because `CommunityFeedRefresh` is constructed at
    /// the app root and reached through the environment, not a singleton — only
    /// a producer that can see it (a View) can supply it. Producers of
    /// `itemsDeleted` / `captureCompleted` never need it; every publication-shaped
    /// mutation does.
    init(
        feed: CommunityFeedRefresh? = nil,
        reloadLearningStores: @escaping @MainActor () async -> Void = {
            // reload(), never invalidate(): clearing WordsStore.loaded trips
            // RootView's splash gate and bounces the app back to Splash.
            async let words: Void = WordsStore.shared.reload()
            async let progress: Void = ProgressStore.shared.reload()
            async let stats: Void = StudyStatsStore.shared.reload()
            _ = await (words, progress, stats)
        },
        refreshCapacity: @escaping @MainActor () async -> Void = {
            await AtlasStore.shared.refreshEntitlement()
        }
    ) {
        self.reloadLearningStores = reloadLearningStores
        self.refreshCapacity = refreshCapacity
        self.markFeedStale = { feed?.markNeedsReload() }
    }

    func refresh(after mutation: AtlasMutation) async {
        if mutation.invalidatesPublicFeed {
            self.markFeedStale()
        }
        guard mutation.changesOwnAtlas else { return }
        await self.reloadLearningStores()
        await self.refreshCapacity()
    }
}
