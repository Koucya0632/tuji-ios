import SwiftUI
import StoreKit
#if TUJI_CREDITS_SANDBOX
import UIKit
#endif

struct CreditWalletView: View {
    @State private var wallet: CreditWallet?
    @State private var catalog: CreditCatalog?
    @State private var busy = false
    @State private var message: String?
    @State private var store = StoreKitService.shared
    @State private var owner: UUID?

    private func current(_ id: UUID) -> Bool {
        guard case let .signedIn(user) = AuthService.shared.state else { return false }
        return user.id == id && self.owner == id
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            HStack {
                Image("CreditCan").resizable().scaledToFit().frame(width: 48, height: 48)
                    .foregroundStyle(.tujiInk).accessibilityHidden(true)
                VStack(alignment: .leading) {
                    Text("罐頭點數").font(.tujiH3)
                    Text(self.wallet.map { String($0.available) } ?? "—").font(.tujiH3)
                }
            }
            if let wallet {
                Text(String(
                    format: tujiLocalized("預留 %d 點 · 贈點 %d · 購買點 %d"),
                    wallet.reserved,
                    wallet.giftAvailable,
                    wallet.paidAvailable
                ))
                .font(.tujiLabel).foregroundStyle(.tujiInk3)
                if wallet.reconciliationRequired {
                    Text("退款點數正在核對，新增 AI 工作暫停。").font(.tujiLabel)
                }
            }
            HStack {
                Button(LocalizedStringKey(self.wallet?.benefits.checkedInToday == true ? "今天已簽到" : "每日簽到")) {
                    Task { await self.claim(.creditCheckIn) }
                }
                .disabled(self.busy || self.catalog?.checkInEnabled != true || self.wallet?.benefits
                    .hasLifetime != true || self.wallet?.benefits
                    .checkedInToday == true || self.wallet?.benefits.studiedToday == false ||
                    (self.wallet?.benefits.checkInGrantedThisMonth ?? 0) >= 300)
            }.font(.tujiLabel)
            Text("每月免費贈送 1,000 點").font(.tujiBody)
            Text(String(
                format: tujiLocalized("免費額度剩餘 %d 點 · 簽到點 %d 點"),
                self.wallet?.monthlyAvailable ?? 0,
                self.wallet?.checkInAvailable ?? 0
            ))
            .font(.tujiLabel).foregroundStyle(.tujiInk3)
            Text("每月自動補滿，不累積。簽到點與購買點數不過期。")
                .font(.tujiLabel).foregroundStyle(.tujiInk3)
            Text("每天學習一題後可簽到 10 點，每月最多 300 點。")
                .font(.tujiLabel).foregroundStyle(.tujiInk3)
            ForEach(self.store.creditProducts, id: \.id) { product in
                Button {
                    Task {
                        self.busy = true
                        defer { self.busy = false }
                        do { _ = try await self.store.purchase(product)
                            await self.reload()
                        } catch { self.message = tujiLocalized("付款正在同步，請稍後重試同步，不需再次購買。") }
                    }
                } label: {
                    HStack {
                        Text(String(
                            format: tujiLocalized("加購 %d 點"),
                            self.catalog?.packs.first(where: { $0.productId == product.id })?.points ?? 0
                        ))
                        Spacer()
                        Text(product.displayPrice)
                    }
                }.disabled(self.busy || self.catalog?.purchaseEnabled != true)
            }
            if let message { Text(message).font(.tujiLabel).foregroundStyle(.tujiAlert) }
            Button("重試同步") {
                Task { await self.store.reconcileUnfinished()
                    await self.reload()
                }
            }.disabled(self.busy)
            #if TUJI_CREDITS_SANDBOX
            if let owner, self.current(owner), self.catalog?.matches(environment: "sandbox") == true {
                SandboxCreditRefundView(owner: owner)
                    .id(owner)
            }
            #endif
        }
        .task { await self.reload() }
    }

    private func apply(_ value: CreditWallet) {
        if self.wallet.map({ value.isNewer(than: $0) }) ?? true { self.wallet = value }
    }

    private func reload() async {
        guard case let .signedIn(user) = AuthService.shared.state else { return }
        if self.owner != user.id { self.owner = user.id
            self.wallet = nil
            self.catalog = nil
        }
        do {
            let catalog: CreditCatalog = try await APIClient.shared.get(.creditCatalog)
            guard self.current(user.id) else { return }
            self.catalog = catalog
            let wallet: CreditWallet = try await APIClient.shared.get(.creditWallet)
            guard self.current(user.id) else { return }
            self.apply(wallet)
            self.message = nil
        } catch { self.message = tujiLocalized("暫時無法連線，請重試同步。") }
    }

    private func claim(_ endpoint: Endpoint) async {
        guard case let .signedIn(user) = AuthService.shared.state, self.current(user.id), !self.busy else { return }
        struct Claim: Decodable { let wallet: CreditWallet }
        self.busy = true
        defer { self.busy = false }
        do {
            let result: Claim = try await APIClient.shared.post(endpoint, body: Empty())
            guard self.current(user.id) else { return }
            self.apply(result.wallet)
            self.message = nil
        } catch {
            // A refusal the server names (studied nowhere today yet) says why.
            if case APIError.conflict = error { self.message = error.localizedDescription } else {
                self.message = tujiLocalized("暫時無法完成，請重試同步。")
            }
        }
    }
}

#if TUJI_CREDITS_SANDBOX
/// Uses the authenticated server ledger so finished consumables need no local history override.
private struct SandboxCreditRefundView: View {
    let owner: UUID
    @State private var purchases: [Entry] = []
    @State private var loading = false
    @State private var message: String?

    private struct Page: Decodable {
        let entries: [Entry]
        let wallet: CreditWallet
    }

    private struct Entry: Decodable, Identifiable {
        let id: String
        let kind: String
        let amount: Int
        let reference: String

        var transactionID: UInt64? {
            guard self.kind == "grant", self.amount > 0, self.reference.hasPrefix("apple:") else { return nil }
            guard let id = UInt64(self.reference.dropFirst("apple:".count)), id > 0 else { return nil }
            return id
        }
    }

    private var current: Bool {
        guard case let .signedIn(user) = AuthService.shared.state else { return false }
        return user.id == self.owner
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            Text(verbatim: "沙盒退款測試").font(.tujiH3)
            Button { Task { await self.load() } } label: {
                Text(verbatim: "重新載入測試交易")
            }.disabled(self.loading)
            ForEach(self.purchases) { entry in
                Button { Task { await self.requestRefund(entry) } } label: {
                    Text(verbatim: "測試退款（\(entry.amount) 點）")
                }.disabled(self.loading || !self.current)
            }
            if let message { Text(verbatim: message).font(.tujiLabel) }
        }
        .task { await self.load() }
    }

    private func load() async {
        guard self.current, !self.loading else { return }
        self.loading = true
        defer { self.loading = false }
        self.purchases = []
        do {
            let catalog: CreditCatalog = try await APIClient.shared.get(.creditCatalog)
            guard self.current, catalog.matches(environment: "sandbox") else { return }
            let page: Page = try await APIClient.shared.get(.sandboxCreditLedger)
            guard self.current, page.wallet.environment == "sandbox" else { return }
            self.purchases = page.entries.filter { $0.transactionID != nil }
            self.message = self.purchases.isEmpty ? "尚無可測試退款的購買交易。" : nil
        } catch {
            guard self.current else { return }
            self.message = "暫時無法載入測試交易，請稍後重試。"
        }
    }

    @MainActor
    private func requestRefund(_ entry: Entry) async {
        guard self.current, !self.loading, let id = entry.transactionID else { return }
        self.loading = true
        defer { self.loading = false }
        self.message = "正在開啟 Apple 退款頁…"
        do {
            let catalog: CreditCatalog = try await APIClient.shared.get(.creditCatalog)
            guard self.current, catalog.matches(environment: "sandbox") else { return }
        } catch {
            guard self.current else { return }
            self.message = "暫時無法確認沙盒環境，請稍後重試。"
            return
        }
        guard let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive && $0.windows.contains(where: \.isKeyWindow) })
        else {
            self.message = "請返回 App 畫面後再次開啟退款。"
            return
        }
        do {
            let status = try await Transaction.beginRefundRequest(for: id, in: scene)
            guard self.current else { self.purchases = []
                self.message = nil
                return
            }
            switch status {
            case .success: self.message = "已提交，等待 Apple 退款通知。"
            case .userCancelled: self.message = nil
            @unknown default: self.message = "請重新載入測試交易確認退款狀態。"
            }
        } catch {
            guard self.current else { return }
            self.message = "無法開啟 Apple 退款頁，請稍後重試。"
        }
    }
}
#endif
