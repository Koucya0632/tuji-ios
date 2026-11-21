// 會員與罐頭點數. Presented from every lock and AI 402, and from Settings.
// Sells 永久會員 (a one-time purchase) beside the 罐頭點數 wallet, and offers
// restore. Tuji Pro is no longer sold (2026-10-06) and its holders were moved
// to 永久會員. The server records the entitlement; on success we just dismiss
// and let the quota UI refresh.

import StoreKit
import SwiftUI

/// Debug-only switches. The type exists in every build — a `#Preview` naming a
/// DEBUG-only type breaks the Release build — but outside DEBUG every value is
/// false, so nothing here can reach an App Store build.
enum DebugOverrides {
    static let forceMembershipV2Key = "debug.forceMembershipV2"

    /// Show the paywall as if the server were on policy v2, so the 永久會員
    /// section can be screenshotted for App Review and bought in the sandbox
    /// before the real cutover. Toggled in 我 → 除錯工具.
    ///
    /// Also in TestFlight builds (`TUJI_BETA`): the sandbox purchase can only be
    /// tested from a build with the store bundle id and no local StoreKit file,
    /// which a Debug build is not. App Store builds are a separate Release
    /// archive without the flag (release.yml), so this cannot ship.
    static var forceMembershipV2: Bool {
        #if DEBUG || TUJI_BETA
        UserDefaults.standard.bool(forKey: forceMembershipV2Key)
        #else
        false
        #endif
    }
}

/// What the paywall offers, decided from the server's three-tier view. Pure so
/// the cutover rules are testable without StoreKit.
struct PaywallOffer: Equatable {
    /// The 永久會員 section exists only under policy v2: before the cutover a
    /// lifetime purchase would buy nothing, so it must not be sold.
    let showsLifetime: Bool
    let ownsLifetime: Bool

    static func from(tier: MembershipTier, membership: Membership?, forceV2: Bool = false) -> PaywallOffer {
        PaywallOffer(
            showsLifetime: MemberAccess.policy(of: membership, forceV2: forceV2) == .v2,
            ownsLifetime: tier == .lifetime || membership?.lifetime != nil
        )
    }
}

struct PaywallView: View {
    private static let termsURL = URL(string: "https://tuji.nexflow.team/terms") ?? URL(fileURLWithPath: "/")
    private static let privacyURL = URL(string: "https://tuji.nexflow.team/privacy") ?? URL(fileURLWithPath: "/")

    @Environment(\.dismiss) private var dismiss
    @State private var store = StoreKitService.shared
    /// Separate from `store` on purpose: `store` drives the *purchase* flow
    /// (products, spinners, restore), `entitlement` answers whether this
    /// account already has Pro by any route.
    /// Injected rather than a hardcoded `.shared` stored property. `ReportFlow`
    /// names that shape as the defect it was carved out to fix — *no init seam,
    /// so no test could substitute it* — and it survived in eight more places.
    private let entitlement: any EffectiveEntitlementReading

    init(entitlement: any EffectiveEntitlementReading = LiveEffectiveEntitlement.shared) {
        self.entitlement = entitlement
    }

    @State private var errorMessage: String?
    /// True while Product.products(for:) is in flight. Needed because that
    /// call can *succeed with an empty array* (misconfigured store, App Store
    /// hiccup) — without this flag the paywall showed an infinite spinner with
    /// no price, no error, and no way to retry.
    @State private var loadingProducts = true

    private var offer: PaywallOffer {
        PaywallOffer.from(
            tier: self.entitlement.tier,
            membership: self.entitlement.membership,
            forceV2: DebugOverrides.forceMembershipV2
        )
    }

    var body: some View {
        TujiFormSheet(title: "會員與罐頭點數") {
            ScrollView {
                VStack(alignment: .leading, spacing: Space.s4) {
                    self.header
                    if self.store.catalog?.billingMode == "credits" {
                        CreditWalletView().tierCard()
                    }
                    if self.offer.showsLifetime {
                        self.lifetimeSection.tierCard()
                    }
                    self.restoreButton
                    self.purchaseNotes
                    self.legal
                }
                .padding(.horizontal, Space.s4)
                .padding(.vertical, Space.s3)
            }
            .task {
                AnalyticsService.shared.track(.paywallView)
                await self.store.loadProducts()
                self.loadingProducts = false
                await self.store.refreshFromCurrentEntitlements()
            }
        }
    }

    /// The sentence that sells, under the sheet title — only while there is
    /// still a 永久會員 to buy.
    private var header: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Image(systemName: "crown.fill")
                .font(.tujiIcon(34, weight: .heavy))
                .foregroundStyle(.tujiCurrent)
            if self.offer.showsLifetime, !self.offer.ownsLifetime {
                Text("一次購買，解鎖全部官方圖鑑和場面。")
                    .font(.tujiH3)
                    .foregroundStyle(.tujiInk)
            }
        }
    }

    private var benefitRows: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            ForEach(MembershipBenefits.lifetime, id: \.key) { row in
                self.benefitRow(icon: row.icon, text: LocalizedStringKey(row.key))
            }
            if self.store.catalog?.billingMode == "credits",
               let policy = self.store.catalog?.policy, let gift = policy.firstPurchaseGift, gift > 0,
               let monthly = policy.monthlyGift
            {
                self.benefitRow(icon: "gift", text: LocalizedStringKey(String(
                    format: tujiLocalized("首購送 %d 點，之後每月送 %d 點"), gift, monthly
                )))
            }
        }
    }

    private var lifetimeSection: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            Text("永久會員")
                .font(.tujiH3)
                .foregroundStyle(.tujiInk)
            self.benefitRows
            if let errorMessage {
                Text(errorMessage)
                    .font(.tujiLabel)
                    .foregroundStyle(.tujiAlert)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(Space.s3)
                    .background(Color.tujiAlert.opacity(0.12), in: .rect(cornerRadius: Radius.r0))
            }
            if self.offer.ownsLifetime {
                Text("你已經是永久會員")
                    .font(.tujiBodySm(.strong))
                    .foregroundStyle(.tujiAccumulation)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else if let product = self.store.lifetimeProduct {
                self.planButton(product)
            } else if self.loadingProducts {
                TujiPageLoading()
            } else {
                // Never a card with no way to buy: say it failed.
                Text("暫時無法載入方案，請檢查網路後再試一次。")
                    .font(.tujiLabel)
                    .foregroundStyle(.tujiInk3)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func benefitRow(icon: String, text: LocalizedStringKey) -> some View {
        HStack(spacing: Space.s3) {
            Image(systemName: icon)
                .font(.tujiIcon(15, weight: .semibold))
                .foregroundStyle(.tujiBrandSecondary)
                .frame(width: 22)
            Text(text)
                .font(.tujiBodySm(.strong))
                .foregroundStyle(.tujiInk)
        }
    }

    private func planButton(_ product: Product) -> some View {
        Button {
            Task { await self.buy(product) }
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(product.displayName)
                        .font(.tujiBody(.strong))
                        .foregroundStyle(.tujiBrandPrimary)
                    Text("一次購買，永久有效")
                        .font(.tujiLabel)
                        .foregroundStyle(.white.opacity(0.85))
                }
                Spacer()
                if self.store.purchasing == product.id {
                    TujiProgressBar(progress: nil, track: .tujiPaper.opacity(0.2), fill: .tujiPaper).frame(width: 56)
                } else {
                    Text(product.displayPrice)
                        .font(.tujiBody(.strong))
                        .foregroundStyle(.white)
                }
            }
            .padding(.horizontal, Space.s3)
            .padding(.vertical, Space.s3)
            .background(.tujiBrandSecondary, in: .rect(cornerRadius: Radius.r0))
        }
        .buttonStyle(.plain)
        .disabled(self.store.purchasing != nil)
    }


    private var restoreButton: some View {
        Button {
            Task { await self.restore() }
        } label: {
            Text("恢復購買")
                .font(.tujiBodySm(.strong))
                .foregroundStyle(.tujiInk3)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
        .disabled(self.store.purchasing != nil)
    }

    /// 購買說明 — what to do when a purchase does not show up, and who handles
    /// refunds. Refunds are Apple's to grant (the server revokes the membership
    /// when Apple reports one), so this says where to ask rather than that there
    /// are none.
    private var purchaseNotes: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Text("購買說明")
                .font(.tujiLabel.weight(.semibold))
                .foregroundStyle(.tujiInk2)
            Group {
                Text("1. 購買後如未生效，請稍等幾分鐘後重新開啟 App。")
                Text("2. 已購買但會員不見了，請依序嘗試：")
                Text("a. 確認登入的是購買時使用的 Tuji 帳號")
                    .padding(.leading, Space.s3)
                Text("b. 點上方的「恢復購買」")
                    .padding(.leading, Space.s3)
                Text("c. 仍然無效，請到 設定 → 意見收集 聯絡我們")
                    .padding(.leading, Space.s3)
                Text("3. 購買與退款由 Apple 處理，退款請向 Apple 申請；退款後會員資格會收回，學習紀錄、詞表與筆記仍會保留。")
                Text("4. 價格以購買時 App Store 顯示的金額為準。")
            }
            .font(.tujiLabel)
            .foregroundStyle(.tujiInk3)
            .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var legal: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Text("永久會員為一次性購買，不會自動續訂。")
                .font(.tujiLabel)
                .foregroundStyle(.tujiInk3)
            // Kept from App Review 3.1.2 (subscriptions): every paywall links
            // the Terms of Use and the privacy policy.
            HStack(spacing: Space.s3) {
                Link("使用條款", destination: Self.termsURL)
                Link("隱私權政策", destination: Self.privacyURL)
            }
            .font(.tujiLabel)
            .foregroundStyle(.tujiBrandSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func buy(_ product: Product) async {
        self.errorMessage = nil
        do {
            let done = try await self.store.purchase(product)
            if done { self.dismiss() }
        } catch {
            self.errorMessage = tujiUserMessage(for: error)
        }
    }

    private func restore() async {
        self.errorMessage = nil
        do {
            try await self.store.restore()
            if self.store.isPro || self.entitlement.tier == .lifetime { self.dismiss() }
        } catch {
            self.errorMessage = tujiUserMessage(for: error)
        }
    }
}

#Preview("not subscribed") {
    PaywallView(entitlement: PreviewEntitlement(isPro: false))
}

#Preview("v2 non-member") {
    PaywallView(entitlement: PreviewEntitlement(
        tier: .free,
        membership: Membership(
            tier: "free", lifetime: nil, proExpiresAt: nil, graceEndsAt: nil,
            canPurchaseLifetime: true, canPurchasePro: true, policy: "v2"
        )
    ))
}

private extension View {
    /// One plan's card on the paywall: a filled, outlined block that reads as
    /// separate from the page and from the other plan.
    func tierCard() -> some View {
        self
            .padding(Space.s3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.tujiPaper2, in: .rect(cornerRadius: Radius.r0))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.r0)
                    .stroke(Color.tujiRule, lineWidth: 1)
            )
    }
}
