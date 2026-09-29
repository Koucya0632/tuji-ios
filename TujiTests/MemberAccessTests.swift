// 會員功能權限: the one rule for whether a member feature shows, and in which
// form — policy × tier × feature × whether the account already has data there.

import Foundation
import Testing
@testable import Tuji

struct MemberAccessTests {
    @Test
    func v1AndUnknownHideEveryFeatureForEveryTier() {
        for policy in [MemberPolicy.v1, .unknown] {
            for tier in [MembershipTier.free, .lifetime, .pro] {
                for feature in MemberFeature.allCases {
                    #expect(MemberAccess.level(feature, policy: policy, tier: tier, hasOwnData: true) == .hidden)
                }
            }
        }
    }

    @Test
    func membersHaveEveryFeatureOpen() {
        for tier in [MembershipTier.lifetime, .pro] {
            for feature in MemberFeature.allCases {
                #expect(MemberAccess.level(feature, policy: .v2, tier: tier) == .open)
            }
        }
    }

    @Test
    func aNonMemberMeetsLocksExceptWhereTheyAlreadyHaveData() {
        #expect(MemberAccess.level(.wordListBrowse, policy: .v2, tier: .free, hasOwnData: false) == .locked)
        #expect(MemberAccess.level(.wordListBrowse, policy: .v2, tier: .free, hasOwnData: true) == .readOnly)
        #expect(MemberAccess.level(.wordNote, policy: .v2, tier: .free, hasOwnData: false) == .locked)
        #expect(MemberAccess.level(.wordNote, policy: .v2, tier: .free, hasOwnData: true) == .readOnly)
        // Adding is the member feature itself: owning lists does not open it.
        #expect(MemberAccess.level(.wordListAdd, policy: .v2, tier: .free, hasOwnData: true) == .locked)
        // The server trims 延伸內容 for a non-member; the app still asks.
        #expect(MemberAccess.level(.wordInsights, policy: .v2, tier: .free) == .open)
    }

    @Test
    func policyComesFromTheServerUnlessDebugForcesV2() {
        #expect(MemberAccess.policy(of: nil, forceV2: false) == .unknown)
        #expect(MemberAccess.policy(of: nil, forceV2: true) == .v2)
        #expect(MemberAccess.policy(of: membership("v1"), forceV2: false) == .v1)
        #expect(MemberAccess.policy(of: membership("v2"), forceV2: false) == .v2)
    }

    @Test @MainActor
    func buyingChangesTheSignatureTheAppRootReloadsOn() {
        let entitlement = FakeEntitlement()
        entitlement.membership = membership("v2")
        let access = LiveMemberAccess(entitlement: entitlement, forceV2: { false })
        let before = access.signature
        #expect(access.level(.wordListAdd) == .locked)
        entitlement.tier = .lifetime
        #expect(access.signature != before)
        #expect(access.level(.wordListAdd) == .open)
    }
}

@MainActor
private final class FakeEntitlement: EffectiveEntitlementReading {
    var tier: MembershipTier = .free
    var membership: Membership?
    var isPro: Bool {
        self.tier == .pro
    }
}

private func membership(_ policy: String) -> Membership {
    Membership(
        tier: "free",
        lifetime: nil,
        proExpiresAt: nil,
        graceEndsAt: nil,
        canPurchaseLifetime: true,
        canPurchasePro: true,
        policy: policy,
        studyableCategories: nil
    )
}
