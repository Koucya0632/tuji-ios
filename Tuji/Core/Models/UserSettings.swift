// Server-side user_settings row + the response shape POST /api/users/settings
// returns. Field names match what `lib/settings.normalizeSettings` produces
// on the backend (snake_case via JSONEncoder.tuji's keyEncodingStrategy).

import Foundation

struct UserSettings: Codable, Sendable, Equatable {
    var dailyGoal: Int
    var accent: String
    var showZh: Bool
    var studyCategory: String
    var studyCategories: String
    var studyDecks: String
    var uiLang: String
    var fontSize: String

    static let `default` = UserSettings(
        dailyGoal: 10,
        accent: "us",
        showZh: true,
        studyCategory: "all",
        studyCategories: "",
        studyDecks: "",
        uiLang: "zh-Hant",
        fontSize: "md"
    )
}

struct SaveSettingsResponse: Decodable, Sendable {
    let ok: Bool?
    let settings: UserSettings?
}
