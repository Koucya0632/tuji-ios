// Pins AtlasStore's merge, its by-image index, the incremental-vs-full sync
// scope, and the sign-out generation fence — none of which had any coverage
// while `init` was private and `AtlasStore.shared` was the only instance that
// could exist.

import Foundation
import Testing
@testable import Tuji

@MainActor
struct AtlasStoreTests {
    @Test
    func syncIndexesItemsByTheImageThatProducedThem() async {
        let fake = FakeAtlasAuthoring()
        fake.syncResponse = AtlasFixtures.syncResponse(
            images: [AtlasFixtures.image("i1"), AtlasFixtures.image("i2")],
            items: [AtlasFixtures.item("t1", imageId: "i1")]
        )
        let store = AtlasStore(repository: fake)

        await store.sync(.full)

        #expect(store.images.count == 2)
        #expect(store.itemsByImageId["i1"]?.id == "t1")
        #expect(store.itemsByImageId["i2"] == nil)
    }

    @Test
    func syncDropsRowsTheServerMarkedDeleted() async {
        let fake = FakeAtlasAuthoring()
        fake.syncResponse = AtlasFixtures.syncResponse(
            images: [
                AtlasFixtures.image("live"),
                AtlasFixtures.image("gone", deletedAt: "2026-01-02T00:00:00Z")
            ],
            items: [AtlasFixtures.item("t1", imageId: "gone", deletedAt: "2026-01-02T00:00:00Z")]
        )
        let store = AtlasStore(repository: fake)

        await store.sync(.full)

        #expect(store.images.map(\.id) == ["live"])
        #expect(store.items.isEmpty)
        #expect(store.itemsByImageId.isEmpty)
    }

    @Test
    func fullScopeIgnoresTheCursorThatIncrementalFollows() async {
        let fake = FakeAtlasAuthoring()
        fake.syncResponse = AtlasFixtures.syncResponse(serverTime: "T-SERVER")
        let store = AtlasStore(repository: fake)

        await store.sync(.full) // first ever: nothing to be incremental from
        await store.sync() // incremental — picks up the stored cursor
        await store.sync(.full) // explicitly everything again

        #expect(fake.syncSinceLog == [nil, "T-SERVER", nil])
    }

    @Test
    func syncFailureSurfacesAsLastErrorRatherThanAnEmptyShelf() async {
        let fake = FakeAtlasAuthoring()
        fake.syncError = AtlasFakeError.boom
        let store = AtlasStore(repository: fake)

        await store.sync(.full)

        #expect(store.lastError != nil)
        #expect(store.images.isEmpty)
        #expect(!store.loading)
    }

    @Test
    func deleteImageDropsItsItemAndItsIndexEntry() async throws {
        let fake = FakeAtlasAuthoring()
        fake.syncResponse = AtlasFixtures.syncResponse(
            images: [AtlasFixtures.image("i1"), AtlasFixtures.image("i2")],
            items: [
                AtlasFixtures.item("t1", imageId: "i1"),
                AtlasFixtures.item("t2", imageId: "i2")
            ]
        )
        let store = AtlasStore(repository: fake)
        await store.sync(.full)

        try await store.deleteImage(id: "i1")

        #expect(store.images.map(\.id) == ["i2"])
        #expect(store.items.map(\.id) == ["t2"])
        #expect(store.itemsByImageId["i1"] == nil)
        #expect(store.itemsByImageId["i2"]?.id == "t2")
    }

    /// The fence every other mutation already had. A delete that lands after
    /// sign-out must not reach into the next account's shelf — which it would,
    /// for any image id the two accounts happen to share.
    @Test
    func deleteImageLandingAfterSignOutLeavesTheNextAccountAlone() async throws {
        let fake = FakeAtlasAuthoring()
        fake.syncResponse = AtlasFixtures.syncResponse(images: [AtlasFixtures.image("shared")])
        let store = AtlasStore(repository: fake)
        await store.sync(.full)

        fake.onDeleteImage = {
            // Sign-out, then the next account's shelf loads with the same id.
            store.reset()
            fake.syncResponse = AtlasFixtures.syncResponse(
                images: [AtlasFixtures.image("shared")],
                items: [AtlasFixtures.item("their-item", imageId: "shared")],
                serverTime: "T2"
            )
            await store.sync(.full)
        }

        try await store.deleteImage(id: "shared")

        #expect(store.images.map(\.id) == ["shared"])
        #expect(store.itemsByImageId["shared"]?.id == "their-item")
    }

    @Test
    func resetClearsTheIndexAlongsideTheRows() async throws {
        let fake = FakeAtlasAuthoring()
        fake.syncResponse = AtlasFixtures.syncResponse(
            images: [AtlasFixtures.image("i1")],
            items: [AtlasFixtures.item("t1", imageId: "i1")]
        )
        let store = AtlasStore(repository: fake)
        await store.sync(.full)

        store.reset()

        #expect(store.images.isEmpty)
        #expect(store.items.isEmpty)
        #expect(store.itemsByImageId.isEmpty)
        #expect(store.entitlement == nil)
        // The cursor goes with it, so the next account syncs from scratch.
        await store.sync()
        let lastSince = try #require(fake.syncSinceLog.last)
        #expect(lastSince == nil)
    }

    @Test
    func withdrawReSyncsRatherThanGuessingTheNewStatus() async throws {
        let fake = FakeAtlasAuthoring()
        let store = AtlasStore(repository: fake)

        try await store.withdraw(itemId: "t1")

        #expect(fake.withdrawnIds == ["t1"])
        #expect(!fake.syncSinceLog.isEmpty)
    }
}
