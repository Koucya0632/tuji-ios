// 自製圖鑑 capacity, counting the captures 生成佇列 has not finished.
//
// The gate used to read the server's usage snapshot alone. That snapshot counts
// confirmed items and cannot know about a capture still being made, so at
// capacity − 1 two quick captures both passed and the second died inside the
// queue as a failure whose tile offered a retry that could only fail again.

import Testing
@testable import Tuji

struct AtlasCapacityReadoutTests {
    @Test
    func anAbsentSnapshotStaysPermissive() {
        // The server is the authority and rejects if truly over; blocking on a
        // snapshot that has not arrived would be the UI inventing a limit.
        let readout = AtlasCapacityReadout.of(nil, inFlight: 3)
        #expect(readout.remaining == nil)
        #expect(readout.canCapture)
    }

    @Test
    func aCommittedCaptureAlreadyClaimsItsSlot() {
        let entitlement = AtlasFixtures.entitlement(slots: 49, slotsLimit: 50)
        #expect(AtlasCapacityReadout.of(entitlement, inFlight: 0).remaining == 1)
        // The one free slot is spoken for by a capture already in the queue.
        let claimed = AtlasCapacityReadout.of(entitlement, inFlight: 1)
        #expect(claimed.remaining == 0)
        #expect(!claimed.canCapture)
    }

    @Test
    func remainingClampsRatherThanGoingNegative() {
        let entitlement = AtlasFixtures.entitlement(slots: 50, slotsLimit: 50)
        #expect(AtlasCapacityReadout.of(entitlement, inFlight: 4).remaining == 0)
    }

    @Test
    func slotsHeldByTheQueueDoNotTellTheUserToDeleteSomething() {
        // "刪除一些" is wrong advice when the slots are claimed by captures that
        // are still being made — waiting is what actually works.
        let entitlement = AtlasFixtures.entitlement(slots: 49, slotsLimit: 50)
        let waiting = AtlasCapacityReadout.of(entitlement, inFlight: 1)
        #expect(waiting.message(isPro: false).contains("正在生成"))

        #expect(AtlasCapacityReadout.of(entitlement, inFlight: 0).canCapture)
        let spent = AtlasCapacityReadout.of(
            AtlasFixtures.entitlement(slots: 50, slotsLimit: 50),
            inFlight: 0
        )
        #expect(spent.message(isPro: false).contains("升級"))
        // A Pro account at its own ceiling is not sold anything.
        #expect(!spent.message(isPro: true).contains("升級"))
    }
}
