// 會員功能權限 — whether a member feature shows at all, and in which form.
//
// It used to be answered four times. 付費頁 asked 生效權限 for the policy; 詞表,
// 筆記 and 詞條延伸內容 each kept their own copy of policy and tier, learned
// from their own endpoint on first load and never refreshed. So a person who
// bought 永久會員 from a lock came back to the same lock — 加入詞表 stayed
// locked and 我的筆記 stayed read-only until the app was relaunched.
//
// Now there is one rule, read off the one seam CONTEXT.md names as the only
// place to ask (`EffectiveEntitlementReading`). The feature stores keep their
// data; this decides access. The server still enforces every write — this only
// decides what the app offers.

import Foundation

/// A member feature, at the granularity a screen asks about.
enum MemberFeature: Hashable, CaseIterable {
    /// 我 → 詞表, and the 詞表 screens.
    case wordListBrowse
    /// 單字頁「加入詞表」.
    case wordListAdd
    /// 我的筆記 on a word.
    case wordNote
    /// 詞條延伸內容. The server trims what a non-member sees; the app only needs
    /// to know whether to ask.
    case wordInsights
}

enum MemberAccessLevel: Equatable {
    /// Membership policy v1, or not known yet: nothing is drawn.
    case hidden
    /// A non-member meets a lock that opens the paywall.
    case locked
    /// A non-member who already has something here (a refund): shown, not editable.
    case readOnly
    case open
}

enum MemberPolicy: Equatable {
    case unknown
    case v1
    case v2
}

enum MemberAccess {
    /// The whole rule. `hasOwnData` is whether the account already has something
    /// in this feature — lists to browse, a note on this word.
    static func level(
        _ feature: MemberFeature,
        policy: MemberPolicy,
        tier: MembershipTier,
        hasOwnData: Bool = false
    )
        -> MemberAccessLevel
    {
        guard policy == .v2 else { return .hidden }
        if tier != .free { return .open }
        switch feature {
        case .wordListBrowse: return hasOwnData ? .readOnly : .locked
        case .wordListAdd: return .locked
        case .wordNote: return hasOwnData ? .readOnly : .locked
        case .wordInsights: return .open
        }
    }

    static func policy(of membership: Membership?, forceV2: Bool) -> MemberPolicy {
        if forceV2 { return .v2 }
        guard let membership else { return .unknown }
        return membership.policy == "v2" ? .v2 : .v1
    }
}

/// The read seam screens and stores use.
@MainActor
protocol MemberAccessReading {
    var policy: MemberPolicy { get }
    var tier: MembershipTier { get }
    func level(_ feature: MemberFeature, hasOwnData: Bool) -> MemberAccessLevel
}

extension MemberAccessReading {
    func level(_ feature: MemberFeature) -> MemberAccessLevel {
        self.level(feature, hasOwnData: false)
    }

    /// Changes exactly when an answer above may change — what the app root
    /// watches to reload the member stores after a purchase or a refund.
    var signature: String {
        "\(self.policy)|\(self.tier.rawValue)"
    }
}

@MainActor
struct LiveMemberAccess: MemberAccessReading {
    var entitlement: any EffectiveEntitlementReading = LiveEffectiveEntitlement.shared
    var forceV2: () -> Bool = { DebugOverrides.forceMembershipV2 }

    var policy: MemberPolicy {
        MemberAccess.policy(of: self.entitlement.membership, forceV2: self.forceV2())
    }

    var tier: MembershipTier {
        self.entitlement.tier
    }

    func level(_ feature: MemberFeature, hasOwnData: Bool) -> MemberAccessLevel {
        MemberAccess.level(feature, policy: self.policy, tier: self.tier, hasOwnData: hasOwnData)
    }
}
