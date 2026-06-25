// Single source of truth for backend endpoint paths.
//
// Adding an endpoint = adding a case + adding its path here. Don't
// fabricate URL strings at call sites — APIClient won't build them.

import Foundation

enum Endpoint {
    // MARK: - Auth-protected user endpoints

    case usersMe
    case usersProfile
    case usersSettings
    case usersFavorites
    case usersLearned
    case usersSync
    case usersProgress
    case usersMastery
    case usersTopWords(type: String, limit: Int)
    case usersDeleteAccount
    case usersPushToken
    case usersPushTokenDelete(deviceId: String)

    // MARK: - Study (auth-protected)

    case studyQueue(mode: String, limit: Int, new: Int, categories: [String])
    case studyAnswer
    case studyStats
    case studyReports

    // MARK: - Public

    case search(q: String)
    case events
    case words(lang: String, learning: String)
    case word(id: String, lang: String, learning: String)
    case categories(lang: String)

    // MARK: - Smoke (temporary; delete with the backend endpoint)

    case smokeWhoami

    // MARK: -

    var path: String {
        switch self {
        case .usersMe: "/api/users/me"
        case .usersProfile: "/api/users/profile"
        case .usersSettings: "/api/users/settings"
        case .usersFavorites: "/api/users/favorites"
        case .usersLearned: "/api/users/learned"
        case .usersSync: "/api/users/sync"
        case .usersProgress: "/api/users/progress"
        case .usersMastery: "/api/users/mastery"
        case .usersTopWords: "/api/users/top-words"
        case .usersDeleteAccount: "/api/users/delete-account"
        case .usersPushToken,
             .usersPushTokenDelete: "/api/users/push-token"
        case .studyQueue: "/api/study/queue"
        case .studyAnswer: "/api/study/answer"
        case .studyStats: "/api/study/stats"
        case .studyReports: "/api/study/reports"
        case .search: "/api/search"
        case .events: "/api/events"
        case .words: "/api/words"
        case let .word(id, _, _): "/api/words/\(id)"
        case .categories: "/api/categories"
        case .smokeWhoami: "/api/test_smoke/whoami"
        }
    }

    var queryItems: [URLQueryItem] {
        switch self {
        case let .studyQueue(mode, limit, new, categories):
            [
                URLQueryItem(name: "mode", value: mode),
                URLQueryItem(name: "limit", value: String(limit)),
                URLQueryItem(name: "new", value: String(new)),
                // Comma-separated category ids; empty = no filter (study all).
                // Backend strips empty / "all" sentinels for us.
                URLQueryItem(name: "category", value: categories.joined(separator: ","))
            ]
        case let .search(q):
            [URLQueryItem(name: "q", value: q)]
        case let .usersPushTokenDelete(deviceId):
            [URLQueryItem(name: "deviceId", value: deviceId)]
        case let .usersTopWords(type, limit):
            [
                URLQueryItem(name: "type", value: type),
                URLQueryItem(name: "limit", value: String(limit))
            ]
        case let .words(lang, learning),
             let .word(_, lang, learning):
            [
                URLQueryItem(name: "lang", value: lang),
                URLQueryItem(name: "learning", value: learning)
            ]
        case let .categories(lang):
            [URLQueryItem(name: "lang", value: lang)]
        default:
            []
        }
    }

    /// URLCache behavior for this endpoint. Public endpoints honor the
    /// server's Cache-Control headers; user / mutating endpoints bypass
    /// the cache so writes immediately reflect.
    var cachePolicy: URLRequest.CachePolicy {
        switch self {
        case .words, .word, .categories, .search:
            .useProtocolCachePolicy
        case .studyAnswer, .studyReports, .events, .usersSync, .usersMastery,
             .usersDeleteAccount, .usersPushToken, .usersPushTokenDelete:
            .reloadIgnoringLocalCacheData
        default:
            .useProtocolCachePolicy
        }
    }

    /// Public endpoints that don't require a bearer token. APIClient
    /// skips the AuthService lookup for these.
    ///
    /// smokeWhoami is technically anonymous-friendly (returns null), but
    /// we keep it authed here so MainTabs' button actually exercises
    /// the Bearer path. The backend tolerates either.
    var isPublic: Bool {
        switch self {
        case .events, .search, .word, .words, .categories: true
        default: false
        }
    }
}
