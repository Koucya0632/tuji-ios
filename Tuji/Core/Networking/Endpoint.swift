// Single source of truth for backend endpoint paths.
//
// Adding an endpoint = adding a case + adding its path here. Don't
// fabricate URL strings at call sites — APIClient won't build them.

import Foundation

enum Endpoint: Sendable {
    // MARK: - Auth-protected user endpoints

    case usersMe
    case usersProfile
    case usersSettings
    case usersFavorites
    case usersLearned
    case usersSync
    case usersProgress
    case usersDeleteAccount
    case usersPushToken
    case usersPushTokenDelete(deviceId: String)

    // MARK: - Study (auth-protected)

    case studyQueue(mode: String, limit: Int)
    case studyAnswer
    case studyStats

    // MARK: - Public

    case search(q: String)
    case events
    case word(id: String)

    // MARK: - Smoke (temporary; delete with the backend endpoint)

    case smokeWhoami

    // MARK: -

    var path: String {
        switch self {
        case .usersMe:               "/api/users/me"
        case .usersProfile:          "/api/users/profile"
        case .usersSettings:         "/api/users/settings"
        case .usersFavorites:        "/api/users/favorites"
        case .usersLearned:          "/api/users/learned"
        case .usersSync:             "/api/users/sync"
        case .usersProgress:         "/api/users/progress"
        case .usersDeleteAccount:    "/api/users/delete-account"
        case .usersPushToken,
             .usersPushTokenDelete:  "/api/users/push-token"
        case .studyQueue:            "/api/study/queue"
        case .studyAnswer:           "/api/study/answer"
        case .studyStats:            "/api/study/stats"
        case .search:                "/api/search"
        case .events:                "/api/events"
        case .word(let id):          "/api/words/\(id)"
        case .smokeWhoami:           "/api/test_smoke/whoami"
        }
    }

    var queryItems: [URLQueryItem] {
        switch self {
        case .studyQueue(let mode, let limit):
            return [
                URLQueryItem(name: "mode", value: mode),
                URLQueryItem(name: "limit", value: String(limit)),
            ]
        case .search(let q):
            return [URLQueryItem(name: "q", value: q)]
        case .usersPushTokenDelete(let deviceId):
            return [URLQueryItem(name: "deviceId", value: deviceId)]
        default:
            return []
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
        case .events, .search, .word: true
        default: false
        }
    }
}
