// State behind 打卡: the reward (catalog + wallet) and one month of calendar.
//
// Owned by 首頁 rather than the sheet, so the chip's dot and the sheet read the
// same wallet and a claim inside the sheet clears the dot without a refetch.
// The two halves fail separately: a calendar that will not load still leaves
// the reward card working, and the other way round.

import Foundation
import Observation

@MainActor
@Observable
final class CheckInModel {
    private(set) var catalog: CreditCatalog?
    private(set) var wallet: CreditWallet?
    private(set) var calendar: StudyCalendarMonth?
    private(set) var calendarFailed = false
    private(set) var claiming = false
    /// A sentence for the last failed claim; cleared by the next load or claim.
    private(set) var message: String?

    /// How far back ‹ goes. The calendar has no "first study day" to stop at,
    /// and a year is more history than this sheet is for.
    static let monthsBack = 12

    @ObservationIgnored private var rewardFetchedAt: Date?
    @ObservationIgnored private let repository: CheckInRepository
    @ObservationIgnored private let now: () -> Date

    init(repository: CheckInRepository = LiveCheckInRepository(), now: @escaping () -> Date = Date.init) {
        self.repository = repository
        self.now = now
    }

    func reward(fallbackStudiedToday: Bool) -> CheckInDecision.Reward {
        CheckInDecision.reward(catalog: self.catalog, wallet: self.wallet, fallbackStudiedToday: fallbackStudiedToday)
    }

    // MARK: Reward

    /// For the chip: re-read only when the last read is older than `ttl`.
    func loadRewardIfStale(ttl: TimeInterval = 60) async {
        if let at = self.rewardFetchedAt, self.now().timeIntervalSince(at) < ttl { return }
        await self.loadReward()
    }

    func loadReward() async {
        do {
            let catalog = try await self.repository.loadCatalog()
            self.catalog = catalog
            // A legacy account has no wallet; asking would only collect a 403.
            if catalog.billingMode == "credits", catalog.checkInEnabled {
                try await self.apply(self.repository.loadWallet())
            } else {
                self.wallet = nil
            }
            self.rewardFetchedAt = self.now()
        } catch {
            // Keep whatever was showing; the chip just goes without its dot.
        }
    }

    func claim() async {
        guard !self.claiming else { return }
        self.claiming = true
        defer { self.claiming = false }
        self.message = nil
        do {
            try await self.apply(self.repository.checkIn())
            self.rewardFetchedAt = self.now()
        } catch {
            self.message = error.localizedDescription
            // The refusal usually means the wallet on screen was stale
            // (studied on another device, claimed on another device).
            await self.loadReward()
        }
    }

    private func apply(_ value: CreditWallet) {
        if self.wallet.map({ value.isNewer(than: $0) }) ?? true { self.wallet = value }
    }

    // MARK: Calendar

    /// The month on screen, or nil before the first answer (the server's current month).
    var month: String? {
        self.calendar?.month
    }

    var canShowEarlier: Bool {
        guard let calendar else { return false }
        guard calendar.streak.totalDays > 0 else { return false }
        let back = MonthGrid.monthsBefore(calendar.month, calendar.today.prefix(7).description) ?? 0
        return back < Self.monthsBack
    }

    var canShowLater: Bool {
        guard let calendar else { return false }
        return (MonthGrid.monthsBefore(calendar.month, calendar.today.prefix(7).description) ?? 0) > 0
    }

    func loadCalendar(month: String? = nil) async {
        do {
            self.calendar = try await self.repository.loadCalendar(month: month ?? self.month)
            self.calendarFailed = false
        } catch {
            self.calendarFailed = self.calendar == nil
        }
    }

    func showMonth(offset: Int) async {
        guard let month = self.month, let target = MonthGrid.shift(month, by: offset) else { return }
        if offset < 0, !self.canShowEarlier { return }
        if offset > 0, !self.canShowLater { return }
        await self.loadCalendar(month: target)
    }
}
