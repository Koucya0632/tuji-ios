// Pins BlockStore: blocking is optimistic but rolls back on failure, a failed
// load fails *open* rather than emptying the feed, and handles compare
// case-insensitively. Driven through a synchronous FakeBlockListing.

import Foundation
import Testing
@testable import Tuji

@MainActor
struct BlockStoreTests {
    @Test
    func loadPopulatesHandlesLowercased() async {
        let fake = FakeBlockListing()
        fake.handles = ["TJ12345678", "tj87654321"]
        let store = BlockStore(repo: fake)

        await store.loadIfNeeded()

        #expect(store.handles == ["tj12345678", "tj87654321"])
        #expect(store.isBlocked("TJ12345678"))
        #expect(store.isBlocked("tj12345678"))
        #expect(!store.isBlocked("TJ00000000"))
    }

    @Test
    func loadIfNeededOnlyFetchesOnce() async {
        let fake = FakeBlockListing()
        let store = BlockStore(repo: fake)

        await store.loadIfNeeded()
        await store.loadIfNeeded()

        #expect(fake.listCalls == 1)
    }

    /// A block list that failed to load must not hide anything. The alternative
    /// — treating "unknown" as "block everything" — turns one network hiccup
    /// into an empty 物見.
    @Test
    func failedLoadHidesNothing() async {
        let fake = FakeBlockListing()
        fake.listError = BlockFakeError.boom
        let store = BlockStore(repo: fake)

        await store.loadIfNeeded()

        #expect(store.handles.isEmpty)
        #expect(!store.isBlocked("tj12345678"))
        // Not marked loaded, so a later attempt can still succeed.
        #expect(!store.loaded)
    }

    @Test
    func blockIsOptimisticAndRollsBackOnFailure() async {
        let fake = FakeBlockListing()
        fake.blockError = BlockFakeError.boom
        let store = BlockStore(repo: fake)

        let ok = await store.block(handle: "TJ12345678")

        #expect(!ok)
        #expect(!store.isBlocked("TJ12345678"))
    }

    @Test
    func blockSucceedsAndHides() async {
        let store = BlockStore(repo: FakeBlockListing())

        let ok = await store.block(handle: "TJ12345678")

        #expect(ok)
        #expect(store.isBlocked("tj12345678"))
    }

    @Test
    func unblockRestoresTheHandleWhenTheServerRejects() async {
        let fake = FakeBlockListing()
        let store = BlockStore(repo: fake)
        await store.block(handle: "TJ12345678")

        fake.unblockError = BlockFakeError.boom
        let ok = await store.unblock(handle: "TJ12345678")

        #expect(!ok)
        #expect(store.isBlocked("TJ12345678"))
    }

    /// Sign-out must clear it, or the next account on this device inherits the
    /// previous one's blocks and silently loses rows from their feed.
    @Test
    func resetClearsEverything() async {
        let store = BlockStore(repo: FakeBlockListing())
        await store.loadIfNeeded()
        await store.block(handle: "TJ12345678")

        store.reset()

        #expect(store.handles.isEmpty)
        #expect(!store.loaded)
    }

    @Test
    func emptyOrMissingHandleIsNeverBlocked() async {
        let fake = FakeBlockListing()
        fake.handles = ["tj12345678"]
        let store = BlockStore(repo: fake)
        await store.loadIfNeeded()

        #expect(!store.isBlocked(nil))
        #expect(!store.isBlocked(""))
    }
}

private enum BlockFakeError: Error { case boom }

@MainActor
private final class FakeBlockListing: BlockListing {
    var handles: [String] = []
    var listError: Error?
    var blockError: Error?
    var unblockError: Error?
    private(set) var listCalls = 0

    func blockedHandles() async throws -> [String] {
        self.listCalls += 1
        if let listError { throw listError }
        return self.handles
    }

    func block(handle _: String) async throws {
        if let blockError { throw blockError }
    }

    func unblock(handle _: String) async throws {
        if let unblockError { throw unblockError }
    }
}
