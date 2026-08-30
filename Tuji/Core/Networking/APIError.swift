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
    /// 429 `save_limit` — the 收進容量 ceiling (CONTEXT.md). Shares its status
    /// code with the throttle above but gives the opposite advice: waiting
    /// never helps, removing something does. Told apart by the body's `error`,
    /// because changing the status code would land as 「伺服器出了點問題（409）」
    /// on every shipped client.
    case atCapacity(limit: Int?, usage: Int?)
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
        // The app owns this sentence rather than forwarding the server's, which
        // is zh-Hant only and names the thing 「學習項目」 — a word no screen uses.
        // It must not offer 升級: the 收進容量 ceiling is an abuse rail, not a
        // paywall, so the server marks it non-upgradeable.
        case let .atCapacity(limit, _):
            if let limit {
                tujiLocalized("已收進的項目達到上限（\(limit)），移除一些後再加入")
            } else {
                tujiLocalized("已收進的項目達到上限，移除一些後再加入")
            }
        // The body is deliberately NOT shown. For 402/429 above we do prefer
        // the server's copy, because those carry product text we wrote in
        // zh-Hant (the atlas daily-AI cap). A 5xx body is a stack trace or an
        // English infrastructure string, and "Server 500: <raw>" is not
        // something to put in front of a reader. It still reaches the log via
        // `diagnostic`.
        case let .server(s, _):
            tujiLocalized("伺服器出了點問題（\(s)），請稍後再試")
        case let .decoding(e): tujiLocalized("資料解析失敗：\(e.localizedDescription)")
        case let .transport(e): Self.friendlyTransportMessage(for: e)
        case .missingBaseURL: tujiLocalized("TUJI_BASE_URL 未設定")
        }
    }

    /// The raw text, for logs only. Never put this on screen.
    var diagnostic: String {
        switch self {
        case let .server(s, b): "server \(s): \(b ?? "<no body>")"
        case let .decoding(e): "decoding: \(e)"
        case let .transport(e): "transport: \(e)"
        default: String(describing: self)
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
            // Two different answers share this status code. `save_limit` is the
            // 收進容量 ceiling; everything else is a genuine throttle.
            let body = Self.errorBody(from: data)
            if Self.string(body, "error") == "save_limit" {
                throw APIError.atCapacity(
                    limit: Self.int(body, "limit"),
                    usage: Self.int(body, "usage")
                )
            }
            throw APIError.rateLimited(message: Self.string(body, "message"))
        default:
            let body = String(data: data, encoding: .utf8)
            throw APIError.server(status: http.statusCode, body: body)
        }
    }

    /// Pulls a user-facing `message` string out of a JSON error body, if any.
    /// Used for 402 so the server owns the copy (e.g. the atlas daily-AI cap).
    private static func serverMessage(from data: Data) -> String? {
        string(errorBody(from: data), "message")
    }

    /// A JSON error body, parsed once. The 429 branch reads three fields out of
    /// it — which failure this is, and the two numbers behind the ceiling — and
    /// parsing per field would decode the same bytes three times.
    private static func errorBody(from data: Data) -> [String: Any]? {
        try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }

    /// One non-empty string out of an error body. An empty value is the same as
    /// an absent one: it is a sentence nobody can read.
    private static func string(_ body: [String: Any]?, _ key: String) -> String? {
        guard let value = body?[key] as? String, !value.isEmpty else { return nil }
        return value
    }

    /// One integer out of an error body. Optional all the way down: a body that
    /// omits it still has to produce a usable sentence, which is why
    /// `atCapacity` carries `Int?` rather than making the parse a precondition.
    private static func int(_ body: [String: Any]?, _ key: String) -> Int? {
        switch body?[key] {
        case let value as Int: value
        case let value as Double: Int(value)
        case let value as String: Int(value)
        default: nil
        }
    }
}
