// Pins 打卡: which reward card shows, when 首頁's chip gets its dot, how a
// month lays out, and what the model does around a claim. Decisions return
// enums, never copy, so nothing here depends on a bundle or a locale.

import Foundation
import Testing
@testable import Tuji

// MARK: - Fixtures

private func decodeFixture<T: Decodable>(_ json: String) -> T {
    do {
        return try JSONDecoder().decode(T.self, from: Data(json.utf8))
    } catch {
        fatalError("CheckInTests fixture does not decode: \(error)")
    }
}

private func makeCatalog(
    billingMode: String = "credits",
    checkInEnabled: Bool = true,
    daily: Int? = 10,
    cap: Int? = 300
)
    -> CreditCatalog
{
    let policy = daily
        .map {
            #","policy":{"recognition":100,"precision":200,"precisionUpgrade":100,"checkInDaily":\#($0),"checkInMonthlyCap":\#(cap ?? 300)}"#
        } ?? ""
    let json = #"""
    {"billingMode":"\#(billingMode)","environment":"sandbox","purchaseEnabled":true,
     "proNewPurchaseEnabled":false,"operationsEnabled":true,"monthlyEnabled":true,
     "checkInEnabled":\#(checkInEnabled),"packs":[]\#(policy)}
    """#
    return decodeFixture(json)
}

private func makeWallet(
    checkedInToday: Bool = false,
    granted: Int = 0,
    hasLifetime: Bool = true,
    studiedToday: Bool? = true,
    version: String = "1"
)
    -> CreditWallet
{
    let studied = studiedToday.map { #","studiedToday":\#($0)"# } ?? ""
    let json = #"""
    {"available":1000,"reserved":0,"paidAvailable":0,"giftAvailable":1000,
     "walletVersion":"\#(version)","environment":"sandbox","reconciliationRequired":false,
     "benefits":{"monthlyClaimed":true,"checkedInToday":\#(checkedInToday),
       "checkInGrantedThisMonth":\#(granted),"hasLifetime":\#(hasLifetime)\#(studied)}}
    """#
    return decodeFixture(json)
}

private func makeMonth(
    _ month: String = "2026-10",
    today: String = "2026-10-06",
    studied: [String] = []
)
    -> StudyCalendarMonth
{
    StudyCalendarMonth(
        month: month,
        timezone: "Asia/Taipei",
        today: today,
        studiedDays: studied,
        streak: StudyStreak(current: 3, longest: 9, totalDays: 20, todayCount: 4, lastStudyDate: today)
    )
}

// MARK: - Reward

struct CheckInRewardTests {
    private func reward(
        _ catalog: CreditCatalog?,
        _ wallet: CreditWallet?,
        fallback: Bool = false
    )
        -> CheckInDecision.Reward
    {
        CheckInDecision.reward(catalog: catalog, wallet: wallet, fallbackStudiedToday: fallback)
    }

    @Test("no catalog, or check-in paused for a points account, shows nothing")
    func hidden() {
        #expect(self.reward(nil, makeWallet()) == .hidden)
        #expect(self.reward(makeCatalog(checkInEnabled: false), makeWallet()) == .hidden)
        #expect(self.reward(makeCatalog(), nil) == .hidden)
    }

    @Test("an account not on points billing is offered the upgrade")
    func locked() {
        #expect(self.reward(makeCatalog(billingMode: "legacy", checkInEnabled: false), nil) == .locked(daily: 10))
        #expect(self.reward(makeCatalog(), makeWallet(hasLifetime: false)) == .locked(daily: 10))
    }

    @Test("eligible but nothing studied today asks for one answer")
    func needsStudy() {
        #expect(self.reward(makeCatalog(), makeWallet(studiedToday: false)) == .needsStudy(daily: 10))
    }

    @Test("studied and unclaimed is claimable, never more than the month has left")
    func claimable() {
        #expect(self.reward(makeCatalog(), makeWallet()) == .claimable(points: 10))
        #expect(self.reward(makeCatalog(), makeWallet(granted: 295)) == .claimable(points: 5))
    }

    @Test("claimed today wins over everything after it")
    func claimed() {
        #expect(self
            .reward(makeCatalog(), makeWallet(checkedInToday: true, granted: 300, studiedToday: false)) == .claimed)
    }

    @Test("a full month is capped whether or not today was studied")
    func capped() {
        #expect(self.reward(makeCatalog(), makeWallet(granted: 300)) == .capped(cap: 300))
        #expect(self.reward(makeCatalog(), makeWallet(granted: 300, studiedToday: false)) == .capped(cap: 300))
    }

    @Test("an older server without studiedToday falls back to the streak's count")
    func oldServerFallback() {
        #expect(self.reward(makeCatalog(), makeWallet(studiedToday: nil), fallback: false) == .needsStudy(daily: 10))
        #expect(self.reward(makeCatalog(), makeWallet(studiedToday: nil), fallback: true) == .claimable(points: 10))
    }

    @Test("amounts come from the catalog's policy when it sends one")
    func policyAmounts() {
        #expect(self.reward(makeCatalog(daily: 20, cap: 100), makeWallet()) == .claimable(points: 20))
        #expect(self.reward(makeCatalog(daily: nil), makeWallet()) == .claimable(points: CheckInDecision.defaultDaily))
    }

    @Test("the chip's dot means points to collect, and nothing else")
    func badge() {
        #expect(CheckInDecision.chipBadge(.claimable(points: 10)))
        for other: CheckInDecision.Reward in [
            .hidden,
            .locked(daily: 10),
            .needsStudy(daily: 10),
            .claimed,
            .capped(cap: 300)
        ] {
            #expect(!CheckInDecision.chipBadge(other))
        }
    }
}

// MARK: - Month grid

struct MonthGridTests {
    @Test("October 2026 starts on a Thursday")
    func leadingBlanks() throws {
        let sunday = try #require(MonthGrid(month: "2026-10", firstWeekday: 1))
        #expect(sunday.cells.prefix(4).allSatisfy { $0 == nil })
        #expect(sunday.cells[4] == 1)
        let monday = try #require(MonthGrid(month: "2026-10", firstWeekday: 2))
        #expect(monday.cells.prefix(3).allSatisfy { $0 == nil })
        #expect(monday.cells[3] == 1)
        #expect(monday.cells.last == 31)
    }

    @Test("a month starting on the first weekday has no blanks")
    func noBlanks() throws {
        // 2026-02-01 is a Sunday.
        let grid = try #require(MonthGrid(month: "2026-02", firstWeekday: 1))
        #expect(grid.cells.first == 1)
        #expect(grid.cells.count == 28)
    }

    @Test("leap February has 29 days")
    func leapYear() throws {
        #expect(try #require(MonthGrid(month: "2028-02", firstWeekday: 1)).cells.compactMap(\.self).count == 29)
    }

    @Test("a month can need six rows")
    func sixRows() throws {
        // 2026-08-01 is a Saturday: six blanks + 31 days = 37 cells.
        let grid = try #require(MonthGrid(month: "2026-08", firstWeekday: 1))
        #expect(grid.cells.count == 37)
        #expect((grid.cells.count + 6) / 7 == 6)
    }

    @Test("dates are zero-padded, month arithmetic crosses years, bad input is refused")
    func arithmetic() throws {
        #expect(try #require(MonthGrid(month: "2026-10", firstWeekday: 1)).date(6) == "2026-10-06")
        #expect(MonthGrid.shift("2026-01", by: -1) == "2025-12")
        #expect(MonthGrid.shift("2026-12", by: 1) == "2027-01")
        #expect(MonthGrid.monthsBefore("2025-10", "2026-10") == 12)
        #expect(MonthGrid(month: "2026-13", firstWeekday: 1) == nil)
        #expect(MonthGrid(month: "October", firstWeekday: 1) == nil)
    }
}

// MARK: - Model

@MainActor
private final class FakeCheckInRepository: CheckInRepository {
    var catalog: CreditCatalog = makeCatalog()
    var wallet: CreditWallet = makeWallet()
    var claimResult: Result<CreditWallet, Error> = .success(makeWallet(checkedInToday: true, version: "2"))
    var calendar: (String?) throws -> StudyCalendarMonth = { makeMonth($0 ?? "2026-10") }
    private(set) var walletReads = 0
    private(set) var calendarMonths: [String?] = []

    func loadCatalog() async throws -> CreditCatalog {
        self.catalog
    }

    func loadWallet() async throws -> CreditWallet {
        self.walletReads += 1
        return self.wallet
    }

    func checkIn() async throws -> CreditWallet {
        try self.claimResult.get()
    }

    func loadCalendar(month: String?) async throws -> StudyCalendarMonth {
        self.calendarMonths.append(month)
        return try self.calendar(month)
    }
}

@MainActor
struct CheckInModelTests {
    @Test("a legacy account never asks for a wallet it does not have")
    func legacySkipsWallet() async {
        let repo = FakeCheckInRepository()
        repo.catalog = makeCatalog(billingMode: "legacy", checkInEnabled: false)
        let model = CheckInModel(repository: repo)
        await model.loadReward()
        #expect(repo.walletReads == 0)
        #expect(model.reward(fallbackStudiedToday: true) == .locked(daily: 10))
    }

    @Test("a claim swaps in the returned wallet and clears the dot")
    func claimClearsBadge() async {
        let repo = FakeCheckInRepository()
        let model = CheckInModel(repository: repo)
        await model.loadReward()
        #expect(CheckInDecision.chipBadge(model.reward(fallbackStudiedToday: false)))
        await model.claim()
        #expect(model.reward(fallbackStudiedToday: false) == .claimed)
        #expect(model.message == nil)
    }

    @Test("a refused claim says why and re-reads the wallet")
    func refusedClaim() async {
        let repo = FakeCheckInRepository()
        repo.claimResult = .failure(APIError.conflict(reason: "check_in_requires_study", message: nil))
        let model = CheckInModel(repository: repo)
        await model.loadReward()
        repo.wallet = makeWallet(studiedToday: false, version: "2")
        await model.claim()
        #expect(model.message != nil)
        #expect(repo.walletReads == 2)
        #expect(model.reward(fallbackStudiedToday: false) == .needsStudy(daily: 10))
    }

    @Test("the chip's read is skipped while fresh")
    func ttl() async {
        let repo = FakeCheckInRepository()
        var now = Date(timeIntervalSince1970: 0)
        let model = CheckInModel(repository: repo, now: { now })
        await model.loadRewardIfStale(ttl: 60)
        await model.loadRewardIfStale(ttl: 60)
        #expect(repo.walletReads == 1)
        now = now.addingTimeInterval(61)
        await model.loadRewardIfStale(ttl: 60)
        #expect(repo.walletReads == 2)
    }

    @Test("month paging stops at the current month and a year back")
    func paging() async {
        let repo = FakeCheckInRepository()
        let model = CheckInModel(repository: repo)
        await model.loadCalendar()
        #expect(!model.canShowLater)
        #expect(model.canShowEarlier)
        await model.showMonth(offset: 1)
        #expect(repo.calendarMonths == [nil])
        await model.showMonth(offset: -1)
        #expect(model.month == "2026-09")
        #expect(model.canShowLater)
        repo.calendar = { makeMonth($0 ?? "2026-10") }
        for _ in 0..<20 {
            await model.showMonth(offset: -1)
        }
        #expect(model.month == "2025-10")
        #expect(!model.canShowEarlier)
    }

    @Test("a month that will not load keeps the one on screen")
    func calendarFailure() async {
        let repo = FakeCheckInRepository()
        let model = CheckInModel(repository: repo)
        repo.calendar = { _ in throw URLError(.notConnectedToInternet) }
        await model.loadCalendar()
        #expect(model.calendarFailed)
        repo.calendar = { makeMonth($0 ?? "2026-10") }
        await model.loadCalendar()
        #expect(!model.calendarFailed)
        repo.calendar = { _ in throw URLError(.notConnectedToInternet) }
        await model.showMonth(offset: -1)
        #expect(!model.calendarFailed)
        #expect(model.month == "2026-10")
    }
}
