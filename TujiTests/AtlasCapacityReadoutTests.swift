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
    func slotsHeldByTheQueueAreADifferentBlockerFromASpentLimit() {
        // "刪除一些" is wrong advice when the slots are claimed by captures that
        // are still being made — waiting is what actually works. Asserted on the
        // blocker rather than the sentence: the sentence is resolved through
        // `tujiLocalized`, so its wording follows the running device's language.
        let entitlement = AtlasFixtures.entitlement(slots: 49, slotsLimit: 50)
        #expect(AtlasCapacityReadout.of(entitlement, inFlight: 1).blocker == .waitingOnQueue(1))
        #expect(AtlasCapacityReadout.of(entitlement, inFlight: 0).blocker == nil)

        let spent = AtlasCapacityReadout.of(
            AtlasFixtures.entitlement(slots: 50, slotsLimit: 50),
            inFlight: 0
        )
        #expect(spent.blocker == .atLimit(50))
        // Without a snapshot there is no ceiling to name.
        #expect(AtlasCapacityReadout(remaining: 0, limit: nil, inFlight: 0).blocker == .atUnknownLimit)
    }

    @Test
    func onlyTheCeilingIsSoldTo() {
        // Being told to wait is not an upgrade prompt, and a Pro account at its
        // own ceiling is not sold anything either. Compared against each other
        // rather than against fixed copy, so this holds in every UI language.
        let entitlement = AtlasFixtures.entitlement(slots: 50, slotsLimit: 50)
        let spent = AtlasCapacityReadout.of(entitlement, inFlight: 0)
        #expect(spent.message(isPro: false) != spent.message(isPro: true))

        let waiting = AtlasCapacityReadout.of(
            AtlasFixtures.entitlement(slots: 49, slotsLimit: 50),
            inFlight: 1
        )
        // The wait line says the same thing to both tiers.
        #expect(waiting.message(isPro: false) == waiting.message(isPro: true))
        #expect(waiting.message(isPro: false) != spent.message(isPro: false))
    }
}
