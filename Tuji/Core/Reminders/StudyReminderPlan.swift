// Which days get a 每日提醒, and what each one says.
//
// Local notifications only — no APNs, no server. The app cannot run at the
// reminder's time to ask "has this person studied yet?", so the plan is laid
// out ahead: one notification per day for the next `horizonDays` days, laid
// again every time the app comes to the foreground or the counts change. What
// the device knows *now* only shapes today's entry; later days say the generic
// thing, because tomorrow's due count is not a number the app has.
//
// The horizon is also the give-up rule: someone who does not open the app for a
// week stops being reminded, rather than being nagged forever.

import Foundation

/// A time of day, device-local. Stored as two integers so a time-zone change
/// keeps "20:00" meaning 20:00 wherever the phone now is.
struct ReminderTime: Equatable {
    var hour: Int
    var minute: Int

    static let `default` = ReminderTime(hour: 20, minute: 0)
}

enum StudyReminderPlan {
    /// How many days ahead are laid out at once.
    static let horizonDays = 7

    struct Entry: Equatable {
        /// Stable per calendar day, so laying the plan again replaces a day's
        /// notification instead of stacking a second one beside it.
        let identifier: String
        let fireDate: DateComponents
        /// Today's due count, when it is known and non-zero. Later days are
        /// always `nil`: the count is today's, not theirs.
        let dueCount: Int?
    }

    static let identifierPrefix = "tuji.reminder."

    /// - Parameters:
    ///   - due: the account's due count right now, or `nil` before stats load.
    ///   - studiedToday: today's entry is dropped once the person has studied.
    static func entries(
        now: Date,
        calendar: Calendar,
        time: ReminderTime,
        due: Int?,
        studiedToday: Bool
    )
        -> [Entry]
    {
        let startOfToday = calendar.startOfDay(for: now)
        return (0..<self.horizonDays).compactMap { offset in
            if offset == 0, studiedToday { return nil }
            guard let day = calendar.date(byAdding: .day, value: offset, to: startOfToday),
                  let fire = calendar.date(
                      bySettingHour: time.hour,
                      minute: time.minute,
                      second: 0,
                      of: day
                  ),
                  fire > now
            else { return nil }
            let parts = calendar.dateComponents([.year, .month, .day], from: day)
            let identifier = String(
                format: "%@%04d-%02d-%02d",
                self.identifierPrefix,
                parts.year ?? 0,
                parts.month ?? 0,
                parts.day ?? 0
            )
            var fireDate = parts
            fireDate.hour = time.hour
            fireDate.minute = time.minute
            let dueToday = offset == 0 ? due.flatMap { $0 > 0 ? $0 : nil } : nil
            return Entry(identifier: identifier, fireDate: fireDate, dueCount: dueToday)
        }
    }
}
