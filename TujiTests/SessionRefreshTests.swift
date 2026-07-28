// Pins SessionRefresh — the post-session refresh both completion screens share.
// Asserts the ordering rule (drain → invalidate all → reload all) and the
// conditional second drain when the last word's write is still in flight.

import Foundation
import Testing
@testable import Tuji

@MainActor
struct SessionRefreshTests {
    @Test
    func drainsOnceThenInvalidatesBeforeReloading() async throws {
        var events: [String] = []
        let a = SpyStore("a") { events.append($0) }
        let b = SpyStore("b") { events.append($0) }
        var queueInvalidated = 0
        let drainer = SpyDrainer() // hasPendingWrites == false

        await SessionRefresh(stores: [a, b], invalidateQueue: { queueInvalidated += 1 })
            .run(draining: drainer)

        // One drain, at the short window; no second drain.
        #expect(drainer.drains == [.seconds(2)])
        // Each store invalidated once and reloaded once…
        #expect(events.count(where: { $0 == "a.invalidate" }) == 1)
        #expect(events.count(where: { $0 == "a.reload" }) == 1)
        #expect(events.count(where: { $0 == "b.reload" }) == 1)
        // …with every invalidate before any reload.
        let lastInvalidate = try #require(events.lastIndex { $0.hasSuffix(".invalidate") })
        let firstReload = try #require(events.firstIndex { $0.hasSuffix(".reload") })
        #expect(lastInvalidate < firstReload)
        #expect(queueInvalidated == 1)
    }

    @Test
    func secondDrainAndRefreshWhenWritesStillPending() async {
        var events: [String] = []
        let a = SpyStore("a") { events.append($0) }
        var queueInvalidated = 0
        let drainer = SpyDrainer()
        drainer.hasPendingWrites = true

        await SessionRefresh(stores: [a], invalidateQueue: { queueInvalidated += 1 })
            .run(draining: drainer)

        // Short drain, then the long one; two full refresh passes.
        #expect(drainer.drains == [.seconds(2), .seconds(15)])
        #expect(events.count(where: { $0 == "a.reload" }) == 2)
        #expect(queueInvalidated == 2)
    }
}

@MainActor
private final class SpyStore: RefreshableStore {
    let name: String
    let record: (String) -> Void

    init(_ name: String, record: @escaping (String) -> Void) {
        self.name = name
        self.record = record
    }

    func invalidate() {
        self.record("\(self.name).invalidate")
    }

    func reload() async {
        self.record("\(self.name).reload")
    }
}

@MainActor
private final class SpyDrainer: PendingWriteDraining {
    var hasPendingWrites = false
    private(set) var drains: [Duration] = []

    func drainPendingWrites(within timeout: Duration) async {
        self.drains.append(timeout)
    }
}
