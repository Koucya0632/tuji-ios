// 生效權限 — the one answer to "is this account Pro right now".
//
// Pro reaches an account two ways (see CONTEXT.md → 方案與權限, and ADR-0004):
// an App Store 訂閱, or a manual 贈與. The server unions them and hands the
// result back on `AtlasEntitlement`. `StoreKitService.isPro` knows about
// neither — it only reflects a transaction verified on THIS Apple ID and
// device, so it reads false for a 贈與, for a purchase made on another device,
// and for a subscription that has since been re-bound to another account.
//
// This existed as a correct doc-commented rule inside MeView while 設定 read
// the raw StoreKit flag 120 lines away in another file — and so offered
// 「升級 Pro」 to accounts that already had Pro. One seam, one answer.

import Foundation

/// Read seam for 生效權限. Deliberately one property: callers asking "is this
/// account Pro" must not be able to reach past it to the two sources, because
/// choosing between those sources is the decision this module exists to own.
@MainActor
protocol EffectiveEntitlementReading {
    var isPro: Bool { get }
    /// free / lifetime / pro, by the same rule as `isPro`.
    var tier: MembershipTier { get }
    /// The server's three-tier detail (policy, purchasability, grace), or nil
    /// before the first sync / from a server that predates it.
    var membership: Membership? { get }
}

@MainActor
struct LiveEffectiveEntitlement: EffectiveEntitlementReading {
    static let shared = LiveEffectiveEntitlement()

    private let atlas: AtlasStore
    private let storeKit: StoreKitService

    init(atlas: AtlasStore = .shared, storeKit: StoreKitService = .shared) {
        self.atlas = atlas
        self.storeKit = storeKit
    }

    /// Reading both `@Observable` sources here means SwiftUI tracks them through
    /// this computed property, so views update without observing them directly.
    var isPro: Bool {
        Self.resolve(
            serverPlan: self.atlas.entitlement,
            devicePurchase: self.storeKit.isPro
        )
    }

    var tier: MembershipTier {
        Self.resolveTier(
            serverPlan: self.atlas.entitlement,
            devicePurchase: self.storeKit.isPro
        )
    }

    var membership: Membership? {
        self.atlas.entitlement?.membership
    }

    /// The rule, as a pure function — mirroring the server's `resolveEntitlement`.
    ///
    /// Split out because it is otherwise untestable: `StoreKitService.init` is
    /// private and `isPro` is `private(set)`, so no test can stand one up. The
    /// rule is the part worth pinning; the two property reads above are not.
    ///
    /// The server snapshot wins **whenever we have one, including when it says
    /// free** — a device holding a StoreKit transaction for a subscription since
    /// re-bound to another account (ADR-0005) is not Pro here, and must not be.
    /// The device flag stands in only while the snapshot is unknown (`nil`
    /// before the first sync and after `reset()` on sign-out); falling back to
    /// `false` there would flash 「升級」 at a paying subscriber on every cold launch.
    static func resolve(serverPlan: AtlasEntitlement?, devicePurchase: Bool) -> Bool {
        guard let serverPlan else { return devicePurchase }
        return serverPlan.isPro
    }

    /// The same rule for three tiers. The device flag only knows Pro, so while
    /// the snapshot is unknown it can say pro or free — never lifetime.
    static func resolveTier(serverPlan: AtlasEntitlement?, devicePurchase: Bool) -> MembershipTier {
        guard let serverPlan else { return devicePurchase ? .pro : .free }
        return serverPlan.membershipTier
    }
}

/// The second implementation, so the seam is a seam.
///
/// Deliberately **not** behind `#if DEBUG`: `#Preview` bodies are compiled in
/// release too, so a preview naming a DEBUG-only type breaks the release build
/// while every Debug build — and CI, which builds Debug — stays green.
///
/// Pro state used to be unviewable in a preview: 付費牆, 設定 and 我 all read
/// `LiveEffectiveEntitlement.shared`, which answers for whoever is signed in on
/// the machine rendering the canvas — in practice always "not Pro". Every
/// Pro-side layout was therefore only ever seen on a device with a live
/// subscription.
struct PreviewEntitlement: EffectiveEntitlementReading {
    let tier: MembershipTier
    let membership: Membership?

    var isPro: Bool {
        self.tier == .pro
    }

    init(isPro: Bool) {
        self.tier = isPro ? .pro : .free
        self.membership = nil
    }

    init(tier: MembershipTier, membership: Membership? = nil) {
        self.tier = tier
        self.membership = membership
    }
}
