// StoreKit 2 for Tuji Pro (auto-renewable subscription: monthly + yearly).
//
// The server is the entitlement authority — every verified transaction (initial
// purchase, background renewal, restore) is forwarded to /api/billing/verify,
// which writes user_entitlements. iOS keeps `isPro` only to drive paywall UI;
// quota gating reads AtlasStore.entitlement (the server's snapshot).
//
// Owned by a @MainActor singleton so the Transaction.updates listener keeps
// running for the whole app lifetime (background renewals arrive here).

import Observation
import OSLog
import StoreKit

@MainActor
@Observable
final class StoreKitService {
    static let shared = StoreKitService()

    enum ProductID {
        static let monthly = "app.tuji.pro.monthly"
        static let yearly = "app.tuji.pro.yearly"
        static let all: [String] = [monthly, yearly]
    }

    private(set) var products: [Product] = []
    private(set) var isPro = false
    /// productID currently being purchased (drives per-plan spinners).
    private(set) var purchasing: String?
    private(set) var loadError: Error?

    private var updatesTask: Task<Void, Never>?
    private let repository: BillingRepository
    private let log = Logger(subsystem: "app.tuji.ios", category: "storekit")

    private init(repository: BillingRepository = LiveBillingRepository.shared) {
        self.repository = repository
        // Listen for renewals / revocations / Ask-to-Buy approvals that land
        // outside an explicit purchase() call.
        self.updatesTask = Task { [weak self] in
            for await update in Transaction.updates {
                guard let self else { continue }
                await self.handle(update)
            }
        }
    }

    func loadProducts() async {
        self.loadError = nil
        do {
            let products = try await Product.products(for: ProductID.all)
            self.products = products.sorted { $0.price < $1.price }
        } catch {
            self.loadError = error
            self.log.error("product load failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Purchase a plan. Returns true when a transaction completed (so the caller
    /// can dismiss the paywall); false for user-cancel / pending.
    @discardableResult
    func purchase(_ product: Product) async throws -> Bool {
        self.purchasing = product.id
        defer { self.purchasing = nil }
        let result = try await product.purchase()
        switch result {
        case let .success(verification):
            let transaction = try self.checkVerified(verification)
            try await self.syncEntitlement(jws: verification.jwsRepresentation)
            await transaction.finish()
            return true
        case .userCancelled, .pending:
            return false
        @unknown default:
            return false
        }
    }

    /// Restore purchases: force a StoreKit sync, then re-evaluate current
    /// entitlements and push them to the server.
    func restore() async throws {
        try await AppStore.sync()
        await self.refreshFromCurrentEntitlements()
    }

    /// Re-read the device's active entitlements (e.g. on paywall open) and mark
    /// Pro locally. Also re-syncs to the server so a fresh install reconciles.
    func refreshFromCurrentEntitlements() async {
        var active = false
        for await result in Transaction.currentEntitlements {
            guard let transaction = try? self.checkVerified(result),
                  ProductID.all.contains(transaction.productID)
            else { continue }
            active = true
            try? await self.syncEntitlement(jws: result.jwsRepresentation)
        }
        self.isPro = active
    }

    private func handle(_ result: VerificationResult<Transaction>) async {
        guard let transaction = try? self.checkVerified(result) else { return }
        try? await self.syncEntitlement(jws: result.jwsRepresentation)
        await transaction.finish()
    }

    private func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case let .unverified(_, error): throw error
        case let .verified(safe): return safe
        }
    }

    /// Forward the signed transaction (JWS) to the server (the authority) and
    /// refresh the mirrored atlas entitlement so quota UI updates immediately.
    private func syncEntitlement(jws: String) async throws {
        let tier = try await self.repository.verify(signedTransaction: jws)
        self.isPro = (tier == "pro")
        await AtlasStore.shared.refreshEntitlement()
    }
}
