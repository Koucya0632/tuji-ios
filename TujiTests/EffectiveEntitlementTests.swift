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

import Foundation
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

// MARK: - Three tiers (tuji monorepo docs/MEMBERSHIP_SERVER_DESIGN.md §6)

extension EffectiveEntitlementTests {
    private func snapshot(json: String) throws -> AtlasEntitlement {
        try JSONDecoder().decode(AtlasEntitlement.self, from: Data(json.utf8))
    }

    private static let base = """
    "atlasSlotsLimit": 20, "primaryAiSoftLimitMonthly": 10, "precisionAiLimitMonthly": 0,
    "subscriptionExpiresAt": null,
    "usage": { "atlasSlots": 2, "primaryAiThisMonth": 1, "precisionAiThisMonth": 0 }
    """

    @Test("a lifetime member decodes as lifetime even though plan stays \"free\"")
    func lifetimeMemberDecodes() throws {
        let e = try self.snapshot(json: """
        { "plan": "free", \(Self.base),
          "membership": { "tier": "lifetime", "lifetime": { "source": "appstore", "acquiredAt": "2026-10-01T00:00:00Z" },
                          "proExpiresAt": null, "graceEndsAt": "2026-10-20T00:00:00Z",
                          "canPurchaseLifetime": false, "canPurchasePro": true, "policy": "v2" } }
        """)
        #expect(e.membershipTier == .lifetime)
        #expect(e.isPro == false)
        #expect(e.membership?.graceEndsAt == "2026-10-20T00:00:00Z")
        #expect(e.membership?.canPurchaseLifetime == false)
    }

    @Test("an older server without `membership` still resolves from plan")
    func legacyServerFallsBackToPlan() throws {
        #expect(try self.snapshot(json: "{ \"plan\": \"pro\", \(Self.base) }").membershipTier == .pro)
        #expect(try self.snapshot(json: "{ \"plan\": \"free\", \(Self.base) }").membershipTier == .free)
    }

    @Test("an unknown future tier degrades to the plan, not a crash")
    func unknownTierFallsBackToPlan() throws {
        let e = try self.snapshot(json: """
        { "plan": "free", \(Self.base),
          "membership": { "tier": "platinum", "lifetime": null, "proExpiresAt": null, "graceEndsAt": null,
                          "canPurchaseLifetime": true, "canPurchasePro": true, "policy": "v2" } }
        """)
        #expect(e.membershipTier == .free)
    }

    @Test("tier follows the same rule as isPro: the server wins, the device stands in only while unknown")
    func tierResolution() {
        #expect(LiveEffectiveEntitlement.resolveTier(serverPlan: self.plan("pro"), devicePurchase: false) == .pro)
        #expect(LiveEffectiveEntitlement.resolveTier(serverPlan: self.plan("free"), devicePurchase: true) == .free)
        #expect(LiveEffectiveEntitlement.resolveTier(serverPlan: nil, devicePurchase: true) == .pro)
        #expect(LiveEffectiveEntitlement.resolveTier(serverPlan: nil, devicePurchase: false) == .free)
    }
}

// MARK: - What the paywall offers (membership checklist §6)

extension EffectiveEntitlementTests {
    private func membership(policy: String, lifetime: Bool) -> Membership {
        Membership(
            tier: lifetime ? "lifetime" : "free",
            lifetime: lifetime ? .init(source: "appstore", acquiredAt: "2026-10-01T00:00:00Z") : nil,
            proExpiresAt: nil,
            graceEndsAt: nil,
            canPurchaseLifetime: !lifetime,
            canPurchasePro: true,
            policy: policy
        )
    }

    @Test("before the cutover lifetime is not sold and Pro is unchanged")
    func v1OffersProOnly() {
        let offer = PaywallOffer.from(tier: .free, membership: self.membership(policy: "v1", lifetime: false))
        #expect(offer.showsLifetime == false)
        #expect(offer.proNeedsLifetimeFirst == false)
        #expect(offer.isV2 == false)
        // An older server sends no membership at all: same answer.
        #expect(PaywallOffer.from(tier: .free, membership: nil).showsLifetime == false)
    }

    @Test("v2 non-member: lifetime first, Pro locked behind it")
    func v2NonMemberBuysLifetimeFirst() {
        let offer = PaywallOffer.from(tier: .free, membership: self.membership(policy: "v2", lifetime: false))
        #expect(offer.showsLifetime)
        #expect(offer.ownsLifetime == false)
        #expect(offer.proNeedsLifetimeFirst)
    }

    @Test("v2 lifetime member: owns lifetime, may buy Pro")
    func v2LifetimeMemberMayBuyPro() {
        let offer = PaywallOffer.from(tier: .lifetime, membership: self.membership(policy: "v2", lifetime: true))
        #expect(offer.ownsLifetime)
        #expect(offer.proNeedsLifetimeFirst == false)
    }

    @Test("v2 live Pro is never told to buy lifetime first")
    func v2ProIsNotLocked() {
        let offer = PaywallOffer.from(tier: .pro, membership: self.membership(policy: "v2", lifetime: false))
        #expect(offer.proNeedsLifetimeFirst == false)
    }
}
