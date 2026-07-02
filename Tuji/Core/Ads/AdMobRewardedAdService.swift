// AdMob-backed rewarded ads for the Free card-generation gate (Google Mobile
// Ads SDK 13.x). Non-personalized (npa) per pricing plan §8 — no tracking, no
// ATT prompt. Best-effort: any load/present failure resolves without blocking
// card generation (§3), so the gate never traps a Free user.

import GoogleMobileAds
import OSLog
import UIKit

@MainActor
final class AdMobRewardedAdService: NSObject, RewardedAdService, FullScreenContentDelegate {
    static let shared = AdMobRewardedAdService()

    // Google's public TEST rewarded unit — shows test ads in dev/sandbox.
    // TODO: replace with the real ad unit id (or drive from config) before release.
    private let adUnitID = "ca-app-pub-3940256099942544/1712485313"

    private var loaded: RewardedAd?
    private var isLoading = false
    private var dismissal: CheckedContinuation<Void, Never>?
    private let log = Logger(subsystem: "app.tuji.ios", category: "ads")

    override private init() { super.init() }

    func preload() {
        guard self.loaded == nil, !self.isLoading else { return }
        Task { await self.load() }
    }

    private func load() async {
        guard self.loaded == nil, !self.isLoading else { return }
        self.isLoading = true
        defer { self.isLoading = false }
        do {
            let request = Request()
            // Non-personalized ads — no tracking / ATT (pricing plan §8).
            let extras = Extras()
            extras.additionalParameters = ["npa": "1"]
            request.register(extras)
            self.loaded = try await RewardedAd.load(with: self.adUnitID, request: request)
        } catch {
            self.log.error("rewarded load failed: \(error.localizedDescription, privacy: .public)")
            self.loaded = nil
        }
    }

    func showRewardedAd() async {
        if self.loaded == nil { await self.load() } // last-chance load
        guard let ad = self.loaded, let root = Self.topViewController() else {
            self.loaded = nil
            self.preload()
            return
        }
        self.loaded = nil
        ad.fullScreenContentDelegate = self
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            self.dismissal = cont
            ad.present(from: root) { [weak self] in
                // Reward earned — the gate doesn't need the amount.
                self?.log.info("rewarded ad reward earned")
            }
        }
        self.preload() // warm the next one
    }

    // MARK: - FullScreenContentDelegate

    func adDidDismissFullScreenContent(_ ad: FullScreenPresentingAd) {
        self.finish()
    }

    func ad(
        _ ad: FullScreenPresentingAd,
        didFailToPresentFullScreenContentWithError error: any Error,
    ) {
        self.log.error("rewarded present failed: \(error.localizedDescription, privacy: .public)")
        self.finish()
    }

    private func finish() {
        self.dismissal?.resume()
        self.dismissal = nil
    }

    // MARK: - Presentation context

    private static func topViewController() -> UIViewController? {
        let scene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
        var top = scene?.keyWindow?.rootViewController
        while let presented = top?.presentedViewController {
            top = presented
        }
        return top
    }
}
