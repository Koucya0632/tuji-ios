// Fakes and fixtures for 拍照新增's paid recognition (`CreditCaptureModelTests`).

import Foundation
@testable import Tuji

@MainActor
final class FakeCreditCaptureAPI: CreditCaptureAPI {
    var catalogValue = CreditFixtures.catalog()
    var walletValue = CreditFixtures.wallet(available: 1000, version: "1")
    /// Set, `wallet()` fails with it.
    var walletError: Error?
    var operationsValue: [CreditOperation] = []
    /// Photos `image(id:)` cannot answer for, by id.
    var imageErrors: [String: Error] = [:]
    var quotePoints = 100
    /// Answers to `accept`, then to each `operation(id:)` poll, in order.
    var acceptResult: Result<CreditOperation, Error> = .success(CreditFixtures.operation(state: "reserved"))
    var polls: [Result<CreditOperation, Error>] = []
    var cancelResult = CreditFixtures.operation(state: "released")
    /// Runs inside `accept`, before it answers — lets a test change who is
    /// signed in while the request is in the air.
    var duringAccept: (() -> Void)?

    private(set) var uploads = 0
    struct Quoted: Equatable {
        let mode: CreditCaptureMode
        let target: TargetLanguage
        let uiLanguage: UILanguage
    }

    private(set) var quotes: [Quoted] = []
    private(set) var accepts: [PendingAccept] = []
    private(set) var polled = 0
    private(set) var walletReads = 0

    func catalog() async throws -> CreditCatalog {
        self.catalogValue
    }

    func wallet() async throws -> CreditWallet {
        self.walletReads += 1
        if let error = self.walletError { throw error }
        return self.walletValue
    }

    func operations() async throws -> [CreditOperation] {
        self.operationsValue
    }

    func image(id: String) async throws -> AtlasImageSummary {
        if let error = self.imageErrors[id] { throw error }
        return AtlasFixtures.image(id, status: "uploaded")
    }

    func upload(photo _: Data) async throws -> AtlasImageSummary {
        self.uploads += 1
        return AtlasFixtures.image("img-1", status: "uploaded")
    }

    func quote(
        imageId _: String,
        mode: CreditCaptureMode,
        target: TargetLanguage,
        uiLanguage: UILanguage
    ) async throws
        -> CreditQuote
    {
        self.quotes.append(Quoted(mode: mode, target: target, uiLanguage: uiLanguage))
        return CreditQuote(
            id: "quote-\(self.quotes.count)",
            points: self.quotePoints,
            expiresAt: "2026-10-11T00:00:00Z",
            input: .init(targetLanguage: target.rawValue, feature: mode.feature)
        )
    }

    func accept(_ pending: PendingAccept) async throws -> CreditOperation {
        self.accepts.append(pending)
        self.duringAccept?()
        return try self.acceptResult.get()
    }

    func operation(id _: String) async throws -> CreditOperation {
        self.polled += 1
        guard !self.polls.isEmpty else { return CreditFixtures.operation(state: "committed") }
        return try self.polls.removeFirst().get()
    }

    func cancel(id _: String) async throws -> CreditOperation {
        self.cancelResult
    }
}

@MainActor
final class InMemoryPendingAcceptJournal: PendingAcceptJournal {
    private(set) var stored: [String: PendingAccept] = [:]

    init(_ preloaded: PendingAccept? = nil, account: UUID? = nil, environment: String = "production") {
        if let preloaded, let account { self.stored["\(account):\(environment)"] = preloaded }
    }

    func load(account: UUID, environment: String) -> PendingAccept? {
        self.stored["\(account):\(environment)"]
    }

    func save(_ pending: PendingAccept, account: UUID, environment: String) {
        self.stored["\(account):\(environment)"] = pending
    }

    func clear(account: UUID, environment: String) {
        self.stored["\(account):\(environment)"] = nil
    }
}

@MainActor
final class InMemorySetAsideJournal: SetAsideJournal {
    private(set) var stored: [UUID: Set<String>] = [:]

    func load(account: UUID) -> Set<String> {
        self.stored[account] ?? []
    }

    func add(_ imageId: String, account: UUID) {
        self.stored[account, default: []].insert(imageId)
    }
}

enum CreditFixtures {
    static func catalog(recognition: Int = 100, precision: Int = 200, upgrade: Int = 100) -> CreditCatalog {
        CreditCatalog(
            billingMode: "credits", environment: "production", purchaseEnabled: true,
            proNewPurchaseEnabled: false, operationsEnabled: true, monthlyEnabled: true, checkInEnabled: true,
            packs: [], policy: .init(recognition: recognition, precision: precision, precisionUpgrade: upgrade)
        )
    }

    static func wallet(available: Int, version: String) -> CreditWallet {
        CreditWallet(
            available: available, reserved: 0, paidAvailable: 0, giftAvailable: available,
            walletVersion: version, environment: "production", reconciliationRequired: false,
            benefits: .init(monthlyClaimed: true, checkedInToday: false, checkInGrantedThisMonth: 0, hasLifetime: true)
        )
    }

    static func operation(
        id: String = "op-1",
        state: String,
        feature: String = "atlas.recognize.primary",
        target: String = "en",
        image: String = "img-1",
        card: String? = nil,
        candidates: [CreditCandidate]? = nil,
        correctionField: String? = nil
    )
        -> CreditOperation
    {
        CreditOperation(
            id: id, state: state, feature: feature, targetLanguage: target, imageId: image, points: 100,
            confirmedItemId: card, fulfillmentState: "unclaimed",
            result: candidates.map(CreditOperation.Result.init(candidates:)),
            correctionField: correctionField
        )
    }

    static let keyboard = CreditCandidate(id: "c1", level: "primary", label: "keyboard", zhHant: "鍵盤", gloss: nil)
}
