// Server-side user_settings row + the response shape POST /api/users/settings
// returns. Field names match what `lib/settings.normalizeSettings` produces
// on the backend (snake_case via JSONEncoder.tuji's keyEncodingStrategy).
//
// Wire contract per backend (lib/settings.ts):
//   studyCategories / studyDecks  →  arrays of strings (kebab-case ids)
// The legacy `studyCategory` single-string field that lived on this struct
// during W1 was dropped from the server payload; keeping it here caused
// /api/users/settings POST responses to fail Decodable's missing-key check.

import Foundation

struct UserSettings: Codable, Equatable {
    var dailyGoal: Int
    var accent: String
    var showZh: Bool
    var studyCategories: [String]
    var studyDecks: [String]
    var uiLang: String
    var fontSize: String

    static let `default` = UserSettings(
        dailyGoal: 10,
        accent: "us",
        showZh: true,
        studyCategories: [],
        studyDecks: [],
        uiLang: "zh-Hant",
        fontSize: "md"
    )
}

struct SaveSettingsResponse: Decodable {
    let ok: Bool?
    let settings: UserSettings?
}

/// Wraps the GET /api/users/settings response — backend always returns
/// the settings object under a top-level "settings" key.
struct UserSettingsResponse: Decodable {
    let settings: UserSettings
}

/// Body for POST /api/users/profile.
struct ProfileUpdatePayload: Encodable {
    let nickname: String?
    let avatar: String?
}

struct ProfileUpdateResponse: Decodable {
    let ok: Bool?
    let nickname: String?
    let avatar: String?
}
