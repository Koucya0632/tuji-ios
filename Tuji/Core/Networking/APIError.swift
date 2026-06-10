// Typed errors surfaced by APIClient. Keeps server / network / decode
// failures distinguishable so callers (UI, retries, logs) can handle
// each correctly.

import Foundation

enum APIError: LocalizedError {
    case unauthorized // 401 — token missing / expired / invalid
    case forbidden // 403 — authed but not allowed
    case notFound // 404
    case rateLimited // 429
    case server(status: Int, body: String?)
    case decoding(Error)
    case transport(Error)
    case missingBaseURL

    var errorDescription: String? {
        switch self {
        case .unauthorized: "未授權，請重新登入"
        case .forbidden: "沒有權限"
        case .notFound: "找不到資源"
        case .rateLimited: "請求太頻繁，請稍後再試"
        case let .server(s, b):
            if let b, !b.isEmpty { "Server \(s): \(b)" } else { "Server error \(s)" }
        case let .decoding(e): "資料解析失敗：\(e.localizedDescription)"
        case let .transport(e): "網路錯誤：\(e.localizedDescription)"
        case .missingBaseURL: "TUJI_BASE_URL 未設定"
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
        case 403:
            throw APIError.forbidden
        case 404:
            throw APIError.notFound
        case 429:
            throw APIError.rateLimited
        default:
            let body = String(data: data, encoding: .utf8)
            throw APIError.server(status: http.statusCode, body: body)
        }
    }
}
