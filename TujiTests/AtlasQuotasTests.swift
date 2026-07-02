// AtlasQuotas mirrors lib/atlas/entitlement.ts — pins the clamp rules and
// the "unknown entitlement stays permissive" contract the capture UI relies on.

import Testing
@testable import Tuji

struct AtlasQuotasTests {
    private func entitlement(
        plan: String = "free",
        slots: Int = 3,
        slotsUsed: Int = 0,
        primaryLimit: Int = 20,
        primaryUsed: Int = 0,
        precisionLimit: Int = 0,
        precisionUsed: Int = 0
    )
        -> AtlasEntitlement
    {
        AtlasEntitlement(
            plan: plan,
            atlasSlotsLimit: slots,
            primaryAiSoftLimitMonthly: primaryLimit,
            precisionAiLimitMonthly: precisionLimit,
            adsRequiredForCardGeneration: plan == "free",
            subscriptionExpiresAt: nil,
            usage: AtlasUsage(
                atlasSlots: slotsUsed,
                primaryAiThisMonth: primaryUsed,
                precisionAiThisMonth: precisionUsed
            )
        )
    }

    @Test
    func unknownEntitlementIsPermissive() {
        #expect(AtlasQuotas.remainingSlots(nil) == nil)
        #expect(AtlasQuotas.canCreateItem(nil))
        #expect(AtlasQuotas.remainingPrimaryAi(nil) == nil)
        #expect(AtlasQuotas.precisionAvailable(nil))
        #expect(AtlasQuotas.remainingPrecisionAi(nil) == nil)
    }

    @Test
    func slotsClampToZeroWhenOverLimit() {
        let e = self.entitlement(slots: 3, slotsUsed: 5)
        #expect(AtlasQuotas.remainingSlots(e) == 0)
        #expect(!AtlasQuotas.canCreateItem(e))
    }

    @Test
    func canCreateUntilTheLastSlot() {
        #expect(AtlasQuotas.canCreateItem(self.entitlement(slots: 3, slotsUsed: 2)))
        #expect(!AtlasQuotas.canCreateItem(self.entitlement(slots: 3, slotsUsed: 3)))
    }

    @Test
    func primaryAiRemainingClamps() {
        #expect(AtlasQuotas.remainingPrimaryAi(self.entitlement(primaryLimit: 20, primaryUsed: 8)) == 12)
        #expect(AtlasQuotas.remainingPrimaryAi(self.entitlement(primaryLimit: 20, primaryUsed: 25)) == 0)
    }

    @Test
    func precisionIsProOnly() {
        // Free tier: precision monthly limit 0 → unavailable.
        #expect(!AtlasQuotas.precisionAvailable(self.entitlement(precisionLimit: 0)))
        #expect(AtlasQuotas.precisionAvailable(self.entitlement(plan: "pro", precisionLimit: 30)))
        #expect(AtlasQuotas
            .remainingPrecisionAi(self.entitlement(plan: "pro", precisionLimit: 30, precisionUsed: 31)) == 0)
    }
}
