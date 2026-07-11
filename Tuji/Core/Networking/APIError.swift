// Typed errors surfaced by APIClient. Keeps server / network / decode
// failures distinguishable so callers (UI, retries, logs) can handle
// each correctly.

import Foundation

enum APIError: LocalizedError {
    case unauthorized // 401 — token missing / expired / invalid
    case paymentRequired(message: String?) // 402 — quota/entitlement, upgrade required
    case forbidden // 403 — authed but not allowed
    case notFound // 404
    case rateLimited(message: String?) // 429 — optional server-supplied copy
    case server(status: Int, body: String?)
    case decoding(Error)
    case transport(Error)
    case missingBaseURL

    var errorDescription: String? {
        switch self {
        case .unauthorized: tujiLocalized("未授權，請重新登入")
        case let .paymentRequired(message):
            if let message, !message.isEmpty { message } else { tujiLocalized("已達使用上限，升級後可繼續") }
        case .forbidden: tujiLocalized("沒有權限")
        case .notFound: tujiLocalized("找不到資源")
        case let .rateLimited(message):
            // Prefer the server's user-facing copy (e.g. the atlas daily-AI cap);
            // fall back to a generic throttle message.
            if let message, !message.isEmpty { message } else { tujiLocalized("請求太頻繁，請稍後再試") }
        case let .server(s, b):
            if let b, !b.isEmpty { "Server \(s): \(b)" } else { "Server error \(s)" }
        case let .decoding(e): tujiLocalized("資料解析失敗：\(e.localizedDescription)")
        case let .transport(e): Self.friendlyTransportMessage(for: e)
        case .missingBaseURL: tujiLocalized("TUJI_BASE_URL 未設定")
        }
    }

    /// Maps common `URLError` codes (offline, timeout, unreachable host) to
    /// plain-language Chinese copy instead of Foundation's raw English
    /// description, so weak/no-network states read like the rest of the UI.
    private static func friendlyTransportMessage(for error: Error) -> String {
        guard let urlError = error as? URLError else {
            return tujiLocalized("網路錯誤：\(error.localizedDescription)")
        }
        switch urlError.code {
        case .notConnectedToInternet, .dataNotAllowed, .internationalRoamingOff:
            return tujiLocalized("目前沒有網路連線，請檢查網路設定後再試")
        case .networkConnectionLost:
            return tujiLocalized("網路連線中斷，請稍後再試")
        case .timedOut:
            return tujiLocalized("連線逾時，請檢查網路狀況後再試")
        case .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed:
            return tujiLocalized("無法連接伺服器，請稍後再試")
        default:
            return tujiLocalized("網路錯誤：\(urlError.localizedDescription)")
        }
    }

    /// Maps an HTTPURLResponse status into either silent success (2xx) or
    /// a typed throw.
    static func check(_ resp: URLResponse, data: Data) throws {
        guard let http = resp as? HTTPURLResponse else { return }
        switch http.statusCode {
        case 200..<300:
            return
        case 401:
            throw APIError.unauthorized
        case 402:
            throw APIError.paymentRequired(message: Self.serverMessage(from: data))
        case 403:
            throw APIError.forbidden
        case 404:
            throw APIError.notFound
        case 429:
            throw APIError.rateLimited(message: Self.serverMessage(from: data))
        default:
            let body = String(data: data, encoding: .utf8)
            throw APIError.server(status: http.statusCode, body: body)
        }
    }

    /// Pulls a user-facing `message` string out of a JSON error body, if any.
    /// Used for 429 so the server owns the copy (e.g. the atlas daily-AI cap).
    private static func serverMessage(from data: Data) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let message = object["message"] as? String,
              !message.isEmpty
        else { return nil }
        return message
    }
}
