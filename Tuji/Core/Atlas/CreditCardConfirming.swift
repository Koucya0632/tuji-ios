// The 罐頭點數 half of 生成佇列's network edge, split out like
// `AtlasCardGenerating` so a test can drive a credit job without the server.

import Foundation

/// What the server answered to a 罐頭點數 confirm.
struct CreditConfirmed: Equatable {
    let itemId: String
    /// The server-side fill-in (reading, definitions, examples) the confirm started.
    let fulfillment: CreditOperation.Fulfillment
}

@MainActor
protocol CreditCardConfirming {
    /// Idempotent per operation and candidate — see `CreditConfirmRequest`.
    func confirm(_ request: CreditConfirmRequest) async throws -> CreditConfirmed
    func fulfillment(operationId: String) async throws -> CreditOperation.Fulfillment
    /// 公開景點圖鑑: publish the made card to 物見, then share it at the spot it
    /// carries. Safe to resend: a card already public answers 409 and is shared all the same.
    func publishToSpot(itemId: String, spotId: String) async throws
}

@MainActor
struct LiveCreditCardConfirming: CreditCardConfirming {
    var api: APIClient = .shared

    func confirm(_ request: CreditConfirmRequest) async throws -> CreditConfirmed {
        struct Payload: Encodable {
            let candidateId: String
            let lemma: String
            let displayZhHant: String?
            let displayGloss: String?
            /// Omitted when nil: only the spot id, never the photo's coordinates.
            let spotId: String?
        }
        struct Confirm: Decodable {
            struct Item: Decodable { let id: String }
            let item: Item
            let operation: CreditOperation
        }
        let result: Confirm = try await self.api.post(
            .aiOperationConfirm(id: request.operationId),
            body: Payload(
                candidateId: request.candidateId,
                lemma: request.lemma,
                displayZhHant: request.displayZhHant,
                displayGloss: request.displayGloss,
                spotId: request.spotId
            )
        )
        return CreditConfirmed(itemId: result.item.id, fulfillment: result.operation.fulfillment)
    }

    func fulfillment(operationId: String) async throws -> CreditOperation.Fulfillment {
        let operation: CreditOperation = try await self.api.get(.aiOperation(id: operationId))
        return operation.fulfillment
    }

    func publishToSpot(itemId: String, spotId: String) async throws {
        struct Published: Decodable {}
        struct Body: Encodable {
            let spotId: String
            let shared: Bool
        }
        struct Shared: Decodable {}
        do {
            let _: Published = try await self.api.post(.atlasItemPublish(id: itemId), body: Empty())
        } catch APIError.conflict {}
        // Sharing is allowed while the gate still holds the card for a human:
        // the spot shows it once it is approved.
        let _: Shared = try await self.api.put(.atlasItemSpot(id: itemId), body: Body(spotId: spotId, shared: true))
    }
}
