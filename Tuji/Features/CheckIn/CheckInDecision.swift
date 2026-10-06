// 打卡's decisions, kept out of the views so they can be pinned without a
// bundle or a locale: which reward card shows, whether the 首頁 chip gets its
// dot, how a month lays out, and which streak milestone is next.
//
// The rule they encode: studying *is* the check-in (one word-card answer, the
// same thing the streak counts), and the points are a separate tap to collect.
// Points are a 永久會員 benefit; everyone else gets the calendar and the streak.

import Foundation

enum CheckInDecision {
    enum Reward: Equatable {
        /// Nothing to say: the catalog did not load, or check-in is paused.
        case hidden
        /// Not on points billing — the upgrade is what unlocks it.
        case locked(daily: Int)
        /// Eligible, nothing studied yet today.
        case needsStudy(daily: Int)
        case claimable(points: Int)
        case claimed
        /// This month's cap is already granted.
        case capped(cap: Int)
    }

    static let defaultDaily = 10
    static let defaultMonthlyCap = 300

    /// - Parameter fallbackStudiedToday: for a server that predates
    ///   `benefits.studiedToday`. The streak's `todayCount` is per direction,
    ///   so this can say "not yet" for someone who studied the other language;
    ///   the server's 409 then explains it.
    static func reward(
        catalog: CreditCatalog?,
        wallet: CreditWallet?,
        fallbackStudiedToday: Bool
    )
        -> Reward
    {
        guard let catalog else { return .hidden }
        let daily = catalog.policy?.checkInDaily ?? self.defaultDaily
        let cap = catalog.policy?.checkInMonthlyCap ?? self.defaultMonthlyCap
        guard catalog.billingMode == "credits" else { return .locked(daily: daily) }
        guard catalog.checkInEnabled, let wallet else { return .hidden }
        let benefits = wallet.benefits
        guard benefits.hasLifetime else { return .locked(daily: daily) }
        if benefits.checkedInToday { return .claimed }
        let left = cap - benefits.checkInGrantedThisMonth
        guard left > 0 else { return .capped(cap: cap) }
        guard benefits.studiedToday ?? fallbackStudiedToday else { return .needsStudy(daily: daily) }
        return .claimable(points: min(daily, left))
    }

    /// The dot on 首頁's streak chip: only when a tap would collect something.
    static func chipBadge(_ reward: Reward) -> Bool {
        if case .claimable = reward { return true }
        return false
    }

    // MARK: - Milestones

    /// Mirrors the server's `STREAK_MILESTONES` (tuji-web lib/streak-milestone.ts),
    /// the days `MilestoneView` celebrates.
    static let milestones = [30, 100, 365]

    /// The next milestone above `current` and how many days are left, or nil
    /// past the last one.
    static func nextMilestone(after current: Int) -> (target: Int, daysLeft: Int)? {
        guard let target = self.milestones.first(where: { $0 > current }) else { return nil }
        return (target, target - current)
    }
}

// MARK: - Month grid

/// One calendar month as a 7-column grid: leading blanks, then day 1…n.
struct MonthGrid: Equatable {
    /// YYYY-MM
    let month: String
    /// nil = a blank before day 1.
    let cells: [Int?]

    /// - Parameter firstWeekday: 1 = Sunday … 7 = Saturday (`Calendar` numbering).
    init?(month: String, firstWeekday: Int) {
        guard let (year, m) = Self.parse(month) else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        guard let first = calendar.date(from: DateComponents(year: year, month: m, day: 1)),
              let days = calendar.range(of: .day, in: .month, for: first)?.count
        else { return nil }
        let weekday = calendar.component(.weekday, from: first)
        let leading = (weekday - firstWeekday + 7) % 7
        self.month = month
        self.cells = Array(repeating: nil, count: leading) + (1...days).map { Optional($0) }
    }

    /// YYYY-MM-DD for a day of this month.
    func date(_ day: Int) -> String {
        "\(self.month)-\(String(format: "%02d", day))"
    }

    // MARK: Month arithmetic on YYYY-MM strings

    static func parse(_ month: String) -> (year: Int, month: Int)? {
        let parts = month.split(separator: "-")
        guard parts.count == 2, let y = Int(parts[0]), let m = Int(parts[1]), (1...12).contains(m) else {
            return nil
        }
        return (y, m)
    }

    static func shift(_ month: String, by delta: Int) -> String? {
        guard let (y, m) = self.parse(month) else { return nil }
        let index = y * 12 + (m - 1) + delta
        return String(format: "%04d-%02d", index / 12, index % 12 + 1)
    }

    /// How many months `month` lies before `reference` (0 = same month).
    static func monthsBefore(_ month: String, _ reference: String) -> Int? {
        guard let (y1, m1) = self.parse(month), let (y2, m2) = self.parse(reference) else { return nil }
        return (y2 * 12 + m2) - (y1 * 12 + m1)
    }
}
