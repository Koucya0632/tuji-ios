// Pins the authoring-side refresh policy: which mutations move the user's own
// 自製圖鑑, which invalidate 公開圖鑑's cache, and that the live adapter actually
// dispatches both. Deleting cards used to skip the entitlement refresh (so
// 「已達上限」 outlived the deletion) and an avatar change used to bust the public
// feed even for a draft 合集.

import Foundation
import Testing
@testable import Tuji

@MainActor
struct AtlasMutationRefreshTests {
    // MARK: - Predicates

    @Test
    func onlyOwnAtlasMutationsMoveTheLearningData() {
        #expect(AtlasMutation.itemsDeleted.changesOwnAtlas)
        #expect(AtlasMutation.captureCompleted.changesOwnAtlas)

        #expect(!AtlasMutation.itemWithdrawn.changesOwnAtlas)
        #expect(!AtlasMutation.collectionPublished.changesOwnAtlas)
        #expect(!AtlasMutation.collectionWithdrawn.changesOwnAtlas)
        #expect(!AtlasMutation.collectionDeleted(wasPublic: true).changesOwnAtlas)
        #expect(!AtlasMutation.collectionAvatarChanged(isPublic: true).changesOwnAtlas)
    }

    @Test
    func onlyPublicationMutationsInvalidateTheFeed() {
        #expect(AtlasMutation.itemWithdrawn.invalidatesPublicFeed)
        #expect(AtlasMutation.collectionPublished.invalidatesPublicFeed)
        #expect(AtlasMutation.collectionWithdrawn.invalidatesPublicFeed)

        #expect(!AtlasMutation.itemsDeleted.invalidatesPublicFeed)
        #expect(!AtlasMutation.captureCompleted.invalidatesPublicFeed)
    }

    /// A 合集 that was never on the wall has nothing to invalidate — the old
    /// avatar path marked the feed stale unconditionally.
    @Test
    func aPrivateCollectionsChangesLeaveTheFeedAlone() {
        #expect(AtlasMutation.collectionDeleted(wasPublic: true).invalidatesPublicFeed)
        #expect(!AtlasMutation.collectionDeleted(wasPublic: false).invalidatesPublicFeed)

        #expect(AtlasMutation.collectionAvatarChanged(isPublic: true).invalidatesPublicFeed)
        #expect(!AtlasMutation.collectionAvatarChanged(isPublic: false).invalidatesPublicFeed)
    }

    // MARK: - Live adapter dispatch

    private func refresher(
        feed: CommunityFeedRefresh? = nil,
        onReload: @escaping @MainActor () -> Void,
        onCapacity: @escaping @MainActor () -> Void
    )
        -> LiveAtlasMutationRefresher
    {
        LiveAtlasMutationRefresher(
            feed: feed,
            reloadLearningStores: { onReload() },
            refreshCapacity: { onCapacity() }
        )
    }

    @Test
    func deletingCardsAlsoRefreshesTheQuotaItJustFreed() async {
        var reloads = 0
        var capacityRefreshes = 0
        let refresher = self.refresher(
            onReload: { reloads += 1 },
            onCapacity: { capacityRefreshes += 1 }
        )

        await refresher.refresh(after: .itemsDeleted)

        #expect(reloads == 1)
        #expect(capacityRefreshes == 1)
    }

    @Test
    func aPublicationMutationTouchesNeitherLearningStoreNorQuota() async {
        var reloads = 0
        var capacityRefreshes = 0
        let feed = CommunityFeedRefresh()
        let refresher = self.refresher(
            feed: feed,
            onReload: { reloads += 1 },
            onCapacity: { capacityRefreshes += 1 }
        )

        await refresher.refresh(after: .collectionPublished)

        #expect(reloads == 0)
        #expect(capacityRefreshes == 0)
        #expect(feed.consume())
    }

    @Test
    func aDraftCollectionsAvatarDoesNotMarkTheFeedStale() async {
        let feed = CommunityFeedRefresh()
        let refresher = self.refresher(feed: feed, onReload: {}, onCapacity: {})

        await refresher.refresh(after: .collectionAvatarChanged(isPublic: false))

        #expect(!feed.consume())
    }

    @Test
    func aPublicCollectionsAvatarMarksTheFeedStale() async {
        let feed = CommunityFeedRefresh()
        let refresher = self.refresher(feed: feed, onReload: {}, onCapacity: {})

        await refresher.refresh(after: .collectionAvatarChanged(isPublic: true))

        #expect(feed.consume())
    }
}
