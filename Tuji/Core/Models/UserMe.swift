// API response shells for the Today hero. These mirror the JSON wire
// format from /api/users/me, /api/study/stats, /api/users/progress.
//
// JSONDecoder.tuji is configured with convertFromSnakeCase, so server-
// side `last_study_date` decodes into `lastStudyDate` for free.

import Foundation

struct UserMeUser: Decodable, Hashable {
    let id: String
    let email: String?
    let username: String?
    let avatar: String?
}

struct UserMeResponse: Decodable {
    let user: UserMeUser?
    let favorites: [String]?
    let learned: [String]?
}

struct StudyStats: Decodable, Hashable {
    let total: Int
    let seen: Int
    let due: Int
    let new: Int
}

struct StudyStatsResponse: Decodable {
    let stats: StudyStats
}

struct StudyStreak: Decodable, Hashable {
    let current: Int
    let longest: Int
    let totalDays: Int
    let todayCount: Int
    let lastStudyDate: String?
}

struct ProgressResponse: Decodable {
    let streak: StudyStreak
}
