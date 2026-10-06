import Foundation

struct CreditWallet: Decodable, Equatable {
    struct Benefits: Decodable, Equatable {
        let monthlyClaimed: Bool
        let checkedInToday: Bool
        let checkInGrantedThisMonth: Int
        let hasLifetime: Bool
    }

    let available: Int
    let reserved: Int
    let paidAvailable: Int
    let giftAvailable: Int
    var monthlyAvailable: Int? = nil
    var checkInAvailable: Int? = nil
    let walletVersion: String
    let environment: String
    let reconciliationRequired: Bool
    let benefits: Benefits

    /// Compare decimal BIGINT strings without truncating walletVersion to Int.
    func isNewer(than previous: CreditWallet) -> Bool {
        guard self.environment == previous.environment else { return true }
        if self.walletVersion.count != previous.walletVersion.count {
            return self.walletVersion.count > previous.walletVersion.count
        }
        return self.walletVersion >= previous.walletVersion
    }
}

struct CreditCatalog: Decodable {
    struct Pack: Decodable { let productId: String
        let points: Int
    }

    /// Prices shown before anything is uploaded; a quote that disagrees is never accepted silently.
    struct Policy: Decodable { let recognition: Int?
        let precision: Int?
        let precisionUpgrade: Int?
    }

    let billingMode: String
    let environment: String
    let purchaseEnabled: Bool
    let proNewPurchaseEnabled: Bool
    let operationsEnabled: Bool
    let monthlyEnabled: Bool
    let checkInEnabled: Bool
    let packs: [Pack]
    var policy: Policy? = nil

    func matches(environment expected: String) -> Bool {
        ["production", "sandbox"].contains(expected) && self.environment == expected
    }
}

struct CreditPurchaseDelivery: Decodable {
    let deliveryAck: Bool
    let status: String
    let transactionId: String
    let environment: String

    func permitsFinish(transactionId: String, environment expected: String? = nil) -> Bool {
        self.deliveryAck && self.transactionId == transactionId &&
            ["credited", "duplicate", "revoked"].contains(self.status) &&
            ["production", "sandbox"].contains(self.environment) &&
            (expected == nil || self.environment == expected)
    }
}

struct CreditCandidate: Decodable, Identifiable {
    let id: String
    /// "primary" or "fine" — the two rows of the candidate grid.
    var level: String? = nil
    let label: String
    let zhHant: String
    let gloss: String?
}

struct CreditOperation: Decodable, Identifiable {
    struct Result: Decodable { let candidates: [CreditCandidate] }
    let id: String
    let state: String
    let feature: String
    let targetLanguage: String
    let imageId: String
    let points: Int
    let confirmedItemId: String?
    let fulfillmentState: String
    let result: Result?

    var needsPolling: Bool {
        ["reserved", "running", "reconciling"].contains(self.state) ||
            (self.state == "committed" && ["pending", "running", "reconciling"].contains(self.fulfillmentState))
    }
}

struct CreditQuote: Decodable {
    struct Input: Decodable { let targetLanguage: String
        let feature: String
    }

    let id: String
    let points: Int
    let expiresAt: String
    let input: Input
}
