// Rewarded-ad gate for Free-tier card generation (pricing plan §2/§3).
//
// The GATE (who sees an ad, and when) is provider-agnostic and lives here +
// AtlasCaptureView. The concrete ad SDK plugs in behind this protocol.
//
// Policy (pricing plan §3 — never block a core function on ads):
//   - Free (entitlement.adsRequiredForCardGeneration) watches a rewarded ad
//     before card generation.
//   - Pro skips it entirely — that is what makes "無廣告" a real benefit.
//   - showRewardedAd() is best-effort: it resolves whether the user earned the
//     reward, closed early, or no ad was available. It NEVER blocks or throws,
//     so card creation always proceeds.

import Foundation

@MainActor
protocol RewardedAdService {
    /// Present a rewarded ad, returning when it is dismissed / unavailable.
    func showRewardedAd() async
    /// Preload so the next showRewardedAd() is instant.
    func preload()
}

/// No-op placeholder until a real rewarded-ad SDK (e.g. AdMob GADRewardedAd) is
/// integrated. It resolves immediately, so the Free gate is wired but shows no
/// ad yet — meaning the paywall's "無廣告" benefit is not real for Pro until this
/// is replaced. See docs/ATLAS_PRICING_PLAN.md (launch-blocker).
@MainActor
final class NoopRewardedAdService: RewardedAdService {
    static let shared = NoopRewardedAdService()
    private init() {}

    func showRewardedAd() async {}
    func preload() {}
}

/// The app-wide rewarded-ad service. Swap `NoopRewardedAdService.shared` for the
/// concrete SDK-backed implementation once the ad SDK is added to the project.
@MainActor
enum Ads {
    static let rewarded: RewardedAdService = NoopRewardedAdService.shared
}
