// Tuji Pro paywall. Presented from the capacity banner / an AI-quota 402 in the
// capture flow, and from Settings. Lists the auto-renewable plans (月 / 年),
// buys via StoreKitService, and offers restore. The server records the
// entitlement; on success we just dismiss and let quota UI refresh.

import StoreKit
import SwiftUI

struct PaywallView: View {
    private static let termsURL = URL(string: "https://tuji.nexflow.team/terms") ?? URL(fileURLWithPath: "/")
    private static let privacyURL = URL(string: "https://tuji.nexflow.team/privacy") ?? URL(fileURLWithPath: "/")

    @Environment(\.dismiss) private var dismiss
    @State private var store = StoreKitService.shared
    /// Separate from `store` on purpose: `store` drives the *purchase* flow
    /// (products, spinners, restore), `entitlement` answers whether this
    /// account already has Pro by any route.
    private let entitlement: any EffectiveEntitlementReading = LiveEffectiveEntitlement.shared
    @State private var errorMessage: String?
    /// True while Product.products(for:) is in flight. Needed because that
    /// call can *succeed with an empty array* (misconfigured store, App Store
    /// hiccup) — without this flag the paywall showed an infinite spinner with
    /// no price, no error, and no way to retry.
    @State private var loadingProducts = true

    var body: some View {
        TujiFormSheet(title: "Tuji Pro") {
            ScrollView {
                VStack(alignment: .leading, spacing: Space.s4) {
                    self.header
                    self.benefits
                    self.plans
                    self.restoreButton
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

    /// The sheet header already says "Tuji Pro"; a 34pt 解鎖 Tuji Pro twelve
    /// points under it was the same words twice. What is left is the sentence
    /// that actually sells — promoted out of the caption size it was hiding in.
    private var header: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Image(systemName: "crown.fill")
                .font(.tujiIcon(34, weight: .heavy))
                .foregroundStyle(.tujiCurrent)
            Text("擴充自製圖鑑容量，並解鎖高精度 AI 辨識。")
                .font(.tujiH3)
                .foregroundStyle(.tujiInk)
        }
    }

    private var benefits: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            self.benefitRow(icon: "square.stack.3d.up.fill", text: "自製圖鑑容量提升至 300 格")
            self.benefitRow(icon: "sparkles", text: "AI 辨識次數提升至每月 500 次")
            self.benefitRow(icon: "scope", text: "高精度 AI 辨識（每月 30 次）")
            self.benefitRow(icon: "bolt.fill", text: "優先支援與後續 Pro 功能")
        }
        .padding(Space.s3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.tujiPaper, in: .rect(cornerRadius: Radius.r0))
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

    @ViewBuilder
    private var plans: some View {
        if let errorMessage {
            Text(errorMessage)
                .font(.tujiLabel)
                .foregroundStyle(.tujiAlert)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(Space.s3)
                .background(Color.tujiAlert.opacity(0.12), in: .rect(cornerRadius: Radius.r0))
        }

        // 生效權限, not the purchase flag: a 贈與 account holds no StoreKit
        // transaction but is Pro, and telling it otherwise here is the same
        // lie 設定 used to tell.
        if self.entitlement.isPro {
            Text("你已經是 Tuji Pro，感謝支持！")
                .font(.tujiBodySm(.strong))
                .foregroundStyle(.tujiAccumulation)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else if self.store.products.isEmpty {
            if self.loadingProducts {
                TujiPageLoading()
            } else {
                VStack(spacing: Space.s3) {
                    Text("暫時無法載入方案，請檢查網路後再試一次。")
                        .font(.tujiLabel)
                        .foregroundStyle(.tujiInk3)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    BBtn(
                        title: "重新載入方案",
                        bg: .tujiPaper2,
                        fg: .tujiBrandSecondary,
                        fullWidth: true,
                        icon: "arrow.clockwise"
                    ) {
                        Task {
                            self.loadingProducts = true
                            await self.store.loadProducts()
                            self.loadingProducts = false
                        }
                    }
                }
            }
        } else {
            VStack(spacing: Space.s3) {
                ForEach(self.store.products, id: \.id) { product in
                    self.planButton(product)
                }
            }
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
                    if let period = self.periodLabel(product) {
                        Text(period)
                            .font(.tujiLabel)
                            .foregroundStyle(.white.opacity(0.85))
                    }
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

    private var legal: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Text("訂閱會自動續訂，可隨時在 App Store 帳號設定取消。付款於確認購買時向 Apple ID 收取。")
                .font(.tujiLabel)
                .foregroundStyle(.tujiInk3)
            // App Review 3.1.2: auto-renewable subscriptions must link to the
            // Terms of Use (EULA) and privacy policy from inside the app.
            HStack(spacing: Space.s3) {
                Link("使用條款", destination: Self.termsURL)
                Link("隱私權政策", destination: Self.privacyURL)
            }
            .font(.tujiLabel)
            .foregroundStyle(.tujiBrandSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// zh-Hant period label from the subscription's renewal period.
    private func periodLabel(_ product: Product) -> String? {
        guard let period = product.subscription?.subscriptionPeriod else { return nil }
        switch period.unit {
        case .day: return period.value == 1 ? "每日" : "每 \(period.value) 天"
        case .week: return period.value == 1 ? "每週" : "每 \(period.value) 週"
        case .month: return period.value == 1 ? "每月" : "每 \(period.value) 個月"
        case .year: return period.value == 1 ? "每年" : "每 \(period.value) 年"
        @unknown default: return nil
        }
    }

    private func buy(_ product: Product) async {
        self.errorMessage = nil
        do {
            let done = try await self.store.purchase(product)
            if done { self.dismiss() }
        } catch {
            self.errorMessage = error.localizedDescription
        }
    }

    private func restore() async {
        self.errorMessage = nil
        do {
            try await self.store.restore()
            if self.store.isPro { self.dismiss() }
        } catch {
            self.errorMessage = error.localizedDescription
        }
    }
}

#Preview {
    PaywallView()
}
