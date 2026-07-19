// Server-side user_settings row + the response shape POST /api/users/settings
// returns. Wire format is camelCase both ways; see lib/settings.ts.
//
//   studyCategories / studyDecks  →  arrays of strings (kebab-case ids)
//
// The legacy `studyCategory` single-string field that lived on this struct
// during W1 was dropped from the server payload; keeping it here caused
// /api/users/settings POST responses to fail Decodable's missing-key check.

import Foundation

enum LearningDirection: String, Codable, CaseIterable {
    case zhEn = "zh-en"
    case zhJa = "zh-ja"

    var targetLanguage: TargetLanguage {
        self == .zhJa ? .ja : .en
    }

    var title: String {
        self == .zhJa ? tujiLocalized("日文圖鑑") : tujiLocalized("英文圖鑑")
    }

    var shortTitle: String {
        self == .zhJa ? tujiLocalized("日文") : tujiLocalized("英文")
    }
}

struct UserSettings: Codable, Equatable {
    var dailyGoal: Int
    var accent: String
    var showZh: Bool
    var studyCategories: [String]
    var studyDecks: [String]
    var learningDirection: LearningDirection
    var uiLang: String
    var fontSize: String

    /// Typed view over the wire `uiLang` string. Unknown or legacy codes
    /// read as zh-Hant without disturbing the stored value (computed, so
    /// synthesized Codable/Equatable still use the raw string).
    var uiLanguage: UILanguage {
        get { UILanguage(code: self.uiLang) }
        set { self.uiLang = newValue.rawValue }
    }

    /// Pre-load defaults. `uiLang` follows the device language so a first-run
    /// user's Welcome/onboarding renders in their language before any server
    /// value exists; SettingsStore re-seeds from its UserDefaults mirror on
    /// init so returning users keep their stored choice instead.
    static let `default` = UserSettings(
        dailyGoal: 10,
        accent: "us",
        showZh: true,
        studyCategories: [],
        studyDecks: [],
        learningDirection: .zhEn,
        uiLang: UILanguage.deviceDefault.rawValue,
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
