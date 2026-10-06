import Foundation

/// GET /api/users/study-calendar — one month of the 打卡 calendar.
///
/// A filled day is a day with a word-card answer, bucketed in `timezone`
/// (the phone's, sent as X-Tuji-Timezone): the same rule and the same calendar
/// as the streak, and the same day the check-in reward is claimed against.
struct StudyCalendarMonth: Decodable, Equatable {
    /// YYYY-MM
    let month: String
    let timezone: String
    /// YYYY-MM-DD in `timezone`.
    let today: String
    /// YYYY-MM-DD, ascending.
    let studiedDays: [String]
    let streak: StudyStreak
}
