// 點數明細 — the arithmetic the screen prints, and what a failed load leaves
// on it. The ledger carries changes, not balances, so "餘 N 點" on every row is
// derived; that derivation and the naming of each movement are what is pinned.

import Foundation
import Testing
@testable import Tuji

private func wallet(
    available: Int,
    reserved: Int = 0,
    paid: Int = 0,
    gift: Int = 0,
    monthly: Int? = nil,
    checkIn: Int? = nil,
    resets: String? = nil
)
    -> CreditWallet
{
    CreditWallet(
        available: available,
        reserved: reserved,
        paidAvailable: paid,
        giftAvailable: gift,
        monthlyAvailable: monthly,
        checkInAvailable: checkIn,
        walletVersion: "1",
        environment: "production",
        reconciliationRequired: false,
        benefits: .init(monthlyClaimed: true, checkedInToday: false, checkInGrantedThisMonth: 0, hasLifetime: true),
        nextMonthlyResetAt: resets
    )
}

private func entry(_ id: String, _ kind: String, _ amount: Int, _ reference: String) -> CreditLedgerPage.Entry {
    CreditLedgerPage.Entry(
        id: id,
        kind: kind,
        amount: amount,
        reference: reference,
        createdAt: "2026-10-12T12:22:36.000Z"
    )
}

struct CreditStatementTests {
    /// Newest first, as the server sends them.
    private let entries = [
        entry("5", "commit", -3, "assistant:6f1c"),
        entry("4", "reserve", 0, "assistant:6f1c"),
        entry("3", "commit", -100, "ai:op-1"),
        entry("2", "grant", 10, "benefit:check_in:2026-10-12"),
        entry("1", "grant", 1000, "benefit:monthly:2026-10")
    ]

    @Test
    func eachRowsBalanceIsWhatWasHeldAfterIt() {
        let statement = CreditStatement(page: CreditLedgerPage(entries: self.entries, wallet: wallet(available: 907)))
        #expect(statement.records.map(\.amount) == [-3, -100, 10, 1000])
        #expect(statement.records.map(\.balanceAfter) == [907, 910, 1010, 1000])
    }

    /// A reserve or a release moves points between available and held without
    /// creating or spending any. It would be a row that says "0 點".
    @Test
    func movementsThatChangeNoTotalAreNotRows() {
        let statement = CreditStatement(page: CreditLedgerPage(entries: self.entries, wallet: wallet(available: 907)))
        #expect(statement.records.map(\.id) == ["5", "3", "2", "1"])
    }

    /// Held points are still held: an operation in flight has not spent them,
    /// so the running balance counts them even though `available` does not.
    @Test
    func pointsHeldByARunningOperationCountTowardTheBalance() {
        let page = CreditLedgerPage(
            entries: [entry("2", "reserve", 0, "ai:op-2"), entry("1", "grant", 1000, "benefit:monthly:2026-10")],
            wallet: wallet(available: 900, reserved: 100)
        )
        let statement = CreditStatement(page: page)
        #expect(statement.available == 900)
        #expect(statement.reserved == 100)
        #expect(statement.records.map(\.balanceAfter) == [1000])
    }

    @Test
    func everyMovementHasAName() {
        let cases: [[String]: CreditStatement.Activity] = [
            ["commit", "assistant:6f1c"]: .askedAssistant,
            ["commit", "ai:op-1"]: .recognition,
            ["commit", "something-new"]: .other,
            ["grant", "benefit:monthly:2026-10"]: .monthlyGift,
            ["grant", "benefit:check_in:2026-10-12"]: .checkIn,
            ["grant", "apple:2000001"]: .purchase,
            ["grant", "play:GPA.1234-5678-9012-34567"]: .purchase,
            ["grant", "admin:goodwill"]: .gift,
            ["expire", "42"]: .expired,
            ["refund", "apple:2000001"]: .refund,
            ["compensate", "ai:op-1"]: .returned,
            ["refund_reverse", "apple:2000001"]: .returned,
            ["a-kind-from-the-future", "x"]: .other
        ]
        for (movement, activity) in cases {
            #expect(CreditStatement.Activity(kind: movement[0], reference: movement[1]) == activity)
        }
    }

    @Test
    func theSourcesAreTheWalletsOwnSplit() {
        let page = CreditLedgerPage(
            entries: [],
            wallet: wallet(
                available: 348,
                paid: 3,
                gift: 345,
                monthly: 300,
                checkIn: 40,
                resets: "2026-11-01T00:00:00.000Z"
            )
        )
        let statement = CreditStatement(page: page)
        // 345 gifted, of which 300 monthly and 40 from check-in: 5 came from
        // somewhere else.
        #expect(statement.sources == .init(monthly: 300, checkIn: 40, purchased: 3, otherGift: 5))
        #expect(statement.monthlyExpires == Wire.parseISO("2026-11-01T00:00:00.000Z"))
        #expect(statement.records.isEmpty)
    }

    /// An older wallet payload has no per-source split. Nothing is invented.
    @Test
    func aWalletWithoutASplitShowsItsGiftsAsOther() {
        let statement = CreditStatement(page: CreditLedgerPage(entries: [], wallet: wallet(available: 50, gift: 50)))
        #expect(statement.sources == .init(monthly: 0, checkIn: 0, purchased: 0, otherGift: 50))
        #expect(statement.monthlyExpires == nil)
    }

    @Test
    func aPageDecodesFromTheWire() throws {
        let json = """
        {"entries":[{"id":"7","walletVersion":"9","kind":"commit","amount":-2,"reservedDelta":-2,
          "reference":"assistant:6f1c","createdAt":"2026-10-12T12:22:36.000Z"}],
         "nextCursor":null,
         "wallet":{"available":98,"reserved":0,"paidAvailable":0,"giftAvailable":98,"monthlyAvailable":98,
          "checkInAvailable":0,"walletVersion":"9","environment":"production","serverNow":"2026-10-12T12:22:37.000Z",
          "nextMonthlyResetAt":"2026-11-01T00:00:00.000Z","reconciliationRequired":false,
          "benefits":{"monthlyClaimed":true,"checkedInToday":false,"checkInGrantedThisMonth":0,"hasLifetime":true}}}
        """
        let page = try JSONDecoder().decode(CreditLedgerPage.self, from: Data(json.utf8))
        let statement = CreditStatement(page: page)
        #expect(statement.records.first?.activity == .askedAssistant)
        #expect(statement.records.first?.balanceAfter == 98)
        #expect(statement.records.first?.date != nil)
        #expect(statement.monthlyExpires != nil)
    }
}

@MainActor
private final class StatementSource: CreditStatementReading {
    var result: Result<CreditLedgerPage, Error>
    init(_ result: Result<CreditLedgerPage, Error>) {
        self.result = result
    }

    func loadStatement() async throws -> CreditLedgerPage {
        try self.result.get()
    }
}

@MainActor
struct CreditStatementModelTests {
    private let page = CreditLedgerPage(entries: [], wallet: wallet(available: 12))

    @Test
    func aLoadFillsTheStatement() async {
        let model = CreditStatementModel(repository: StatementSource(.success(self.page)))
        await model.load()
        #expect(model.statement?.available == 12)
        #expect(model.phase == .loaded)
        #expect(model.refusal == nil)
    }

    /// No wallet is not a failure to retry — it is an account that has none.
    @Test
    func anAccountWithoutAWalletIsToldSoRatherThanOfferedARetry() async {
        for error in [APIError.forbidden, APIError.notFound, APIError.unauthorized] {
            let model = CreditStatementModel(repository: StatementSource(.failure(error)))
            await model.load()
            #expect(model.refusal == .notEnrolled)
            #expect(model.statement == nil)
        }
    }

    @Test
    func anUnreachableServerIsARetry() async {
        let model = CreditStatementModel(repository: StatementSource(.failure(APIError.transport(URLError(.timedOut)))))
        await model.load()
        #expect(model.refusal == .unreachable)
        #expect(model.phase == .failed)
    }

    /// A refresh that fails must not blank a statement that was already there.
    @Test
    func aFailedRefreshKeepsWhatWasOnScreen() async {
        let source = StatementSource(.success(self.page))
        let model = CreditStatementModel(repository: source)
        await model.load()
        source.result = .failure(APIError.transport(URLError(.notConnectedToInternet)))
        await model.load()
        #expect(model.statement?.available == 12)
        #expect(model.refusal == nil)
        #expect(model.phase == .loaded)
    }
}
