import Foundation

struct CreditWallet: Decodable, Equatable {
    struct Benefits: Decodable, Equatable {
        let monthlyClaimed: Bool
        let checkedInToday: Bool
        let checkInGrantedThisMonth: Int
        let hasLifetime: Bool
        /// A word-card answer was logged today (the phone's zone), which check-in
        /// requires. nil from a server older than that rule.
        var studiedToday: Bool? = nil
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
    /// When the monthly gift lapses (ISO8601). Optional: older fixtures omit it.
    var nextMonthlyResetAt: String? = nil

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
        var checkInDaily: Int? = nil
        var checkInMonthlyCap: Int? = nil
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

    /// Where one paid recognition stands. **The only place the wire strings are
    /// spelled**: they used to be compared as literals in four files, and "is
    /// it still running" was written out twice as two separate lists.
    enum Status: Equatable {
        /// Accepted, points held, not started. The one state a user can cancel.
        case reserved
        case running
        /// The provider answered ambiguously; the server is settling it.
        case reconciling
        /// Delivered and charged. Candidates are in `result`.
        case committed
        /// Ended without a result. The points were never taken.
        case released
        /// A state this build does not know. Treated as settled, not in flight.
        case other(String)

        init(_ wire: String) {
            self = switch wire {
            case "reserved": .reserved
            case "running": .running
            case "reconciling": .reconciling
            case "committed": .committed
            case "released": .released
            default: .other(wire)
            }
        }

        /// The recognition has not ended, so the screen keeps asking.
        var isInFlight: Bool {
            self == .reserved || self == .running || self == .reconciling
        }
    }

    /// The server-side 補充 a confirm starts (reading, definitions, examples).
    enum Fulfillment: Equatable {
        case pending, running, reconciling
        /// Ended — completed, compensated or superseded — or never started.
        case settled(String)

        init(_ wire: String) {
            self = switch wire {
            case "pending": .pending
            case "running": .running
            case "reconciling": .reconciling
            default: .settled(wire)
            }
        }

        /// It can still land, so 生成佇列 keeps the tile on 補充中.
        var isOpen: Bool {
            if case .settled = self { return false }
            return true
        }
    }

    let id: String
    let state: String
    let feature: String
    let targetLanguage: String
    let imageId: String
    let points: Int
    let confirmedItemId: String?
    let fulfillmentState: String
    let result: Result?
    /// Which second field the correction form shows for this run, when the
    /// server knows the interface language it was quoted under.
    var correctionField: String? = nil

    var status: Status {
        Status(self.state)
    }

    var fulfillment: Fulfillment {
        Fulfillment(self.fulfillmentState)
    }

    var isRunning: Bool {
        self.status.isInFlight
    }
}

extension CreditOperation {
    /// Work already paid for that the screen should reopen on: a run in flight, else a result
    /// nobody has picked from yet. A photo's 普通 and 高精度 runs share one card, so a card made
    /// from either finishes both. One 生成佇列 is already confirming is not waiting either.
    static func resumable(in operations: [CreditOperation], queued: Set<String> = []) -> CreditOperation? {
        let finished = Set(operations.filter { $0.confirmedItemId != nil }.map(\.imageId))
        return operations.first(where: \.isRunning) ?? operations.first {
            $0.status == .committed && $0.confirmedItemId == nil && !finished.contains($0.imageId) &&
                !queued.contains($0.id)
        }
    }

    /// The same question about one photo — what 圖片詳情's 繼續確認 reopens. `resumable(in:)`
    /// answers with the newest photo still waiting, so an older one could only be reached by
    /// finishing every photo taken after it.
    static func resumable(
        for imageId: String,
        in operations: [CreditOperation],
        queued: Set<String> = []
    )
        -> CreditOperation?
    {
        self.resumable(in: operations.filter { $0.imageId == imageId }, queued: queued)
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
