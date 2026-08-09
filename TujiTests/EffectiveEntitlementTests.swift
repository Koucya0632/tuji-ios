// Pins 生效權限 — the one answer to "is this account Pro right now".
//
// THE RED LINE: the server's snapshot wins whenever it exists, in BOTH
// directions. Getting this wrong is not symmetric:
//   - server pro + device false → showing free offers 「升級」 to a 贈與 account
//     that already has Pro (exactly the bug 設定 shipped).
//   - server free + device true → showing Pro hands paid features to a device
//     whose subscription has been re-bound to another account (ADR-0005).
//
// The nil case is the one place the device flag may speak, and it must: a
// paying subscriber would otherwise see 「升級」 flash on every cold launch
// before the first entitlement sync lands.

import Testing
@testable import Tuji

@MainActor
struct EffectiveEntitlementTests {
    private func plan(_ plan: String) -> AtlasEntitlement {
        AtlasEntitlement(
            plan: plan,
            atlasSlotsLimit: 3,
            primaryAiSoftLimitMonthly: 30,
            precisionAiLimitMonthly: 0,
            subscriptionExpiresAt: nil,
            usage: AtlasUsage(atlasSlots: 0, primaryAiThisMonth: 0, precisionAiThisMonth: 0)
        )
    }

    @Test("a 贈與 account is Pro with no StoreKit transaction on the device")
    func grantedAccountIsPro() {
        #expect(
            LiveEffectiveEntitlement.resolve(
                serverPlan: self.plan("pro"),
                devicePurchase: false
            )
        )
    }

    @Test("the server saying free beats a StoreKit transaction on this device")
    func serverFreeBeatsDevicePurchase() {
        #expect(
            LiveEffectiveEntitlement.resolve(
                serverPlan: self.plan("free"),
                devicePurchase: true
            ) == false
        )
    }

    @Test("while the snapshot is unknown the device purchase stands in")
    func unknownSnapshotFallsBackToDevice() {
        #expect(LiveEffectiveEntitlement.resolve(serverPlan: nil, devicePurchase: true))
    }

    @Test("unknown snapshot and no purchase is free")
    func unknownSnapshotWithoutPurchaseIsFree() {
        #expect(
            LiveEffectiveEntitlement.resolve(serverPlan: nil, devicePurchase: false) == false
        )
    }

    @Test("a subscribing account is Pro on a device that has the transaction too")
    func subscriberIsPro() {
        #expect(
            LiveEffectiveEntitlement.resolve(
                serverPlan: self.plan("pro"),
                devicePurchase: true
            )
        )
    }

    @Test("an unrecognised plan string is not Pro")
    func unknownPlanIsNotPro() {
        // The wire value is a bare string; anything we do not recognise must
        // fail closed rather than hand out paid features.
        #expect(
            LiveEffectiveEntitlement.resolve(
                serverPlan: self.plan("trial"),
                devicePurchase: false
            ) == false
        )
    }
}
