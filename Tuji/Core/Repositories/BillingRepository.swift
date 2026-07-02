import Foundation

/// Talks to the billing backend. The server is the entitlement authority: it
/// verifies the signed StoreKit transaction and writes user_entitlements. iOS
/// only forwards the signed payload and re-reads the atlas entitlement after.
@MainActor
protocol BillingRepository {
    /// Send a StoreKit 2 signed transaction (JWS) for server verification.
    /// Returns the tier the server recorded ("pro" / "free").
    func verify(signedTransaction: String) async throws -> String
}

@MainActor
struct LiveBillingRepository: BillingRepository {
    static let shared = LiveBillingRepository()

    private let api: APIClient

    init(api: APIClient = .shared) {
        self.api = api
    }

    func verify(signedTransaction: String) async throws -> String {
        struct Payload: Encodable { let signedTransaction: String }
        struct Response: Decodable { let tier: String? }
        let response: Response = try await self.api.post(
            .billingVerify,
            body: Payload(signedTransaction: signedTransaction)
        )
        return response.tier ?? "free"
    }
}
