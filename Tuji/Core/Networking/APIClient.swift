// Typed HTTP client. Every protected request automatically picks up
// the current access token via AuthService.validAccessToken(). On 401
// retries once after the supabase-swift SDK refreshes the session.
//
// Public endpoints (Endpoint.isPublic) skip the auth lookup entirely.

import Foundation
import OSLog

@MainActor
final class APIClient {
    static let shared = APIClient()

    private let baseURL: URL
    private let auth: AuthService
    private let urlSession: URLSession
    private let decoder: JSONDecoder = .tuji
    private let encoder: JSONEncoder = .tuji
    private let log = Logger(subsystem: "app.tuji.ios", category: "api")

    init(auth: AuthService = .shared, urlSession: URLSession = APIClient.makeCachingSession()) {
        self.auth = auth
        self.urlSession = urlSession

        if let str = Bundle.main.object(forInfoDictionaryKey: "TUJI_BASE_URL") as? String,
           let url = URL(string: str)
        {
            baseURL = url
        } else {
            // Last-resort fallback. SmokeTest used the same one.
            baseURL = URL(string: "https://everyday-english-picture-dictionary.vercel.app")!
            log.error("TUJI_BASE_URL missing from Info.plist; falling back to prod")
        }
    }

    // MARK: - Public API

    @discardableResult
    func get<T: Decodable>(_ ep: Endpoint, as: T.Type = T.self) async throws -> T {
        try await request(ep, method: "GET", body: Empty?.none, decodeAs: T.self)
    }

    @discardableResult
    func post<T: Decodable>(
        _ ep: Endpoint, body: some Encodable, as: T.Type = T.self
    ) async throws
        -> T
    {
        try await request(ep, method: "POST", body: body, decodeAs: T.self)
    }

    @discardableResult
    func put<T: Decodable>(
        _ ep: Endpoint, body: some Encodable, as: T.Type = T.self
    ) async throws
        -> T
    {
        try await request(ep, method: "PUT", body: body, decodeAs: T.self)
    }

    @discardableResult
    func patch<T: Decodable>(
        _ ep: Endpoint, body: some Encodable, as: T.Type = T.self
    ) async throws
        -> T
    {
        try await request(ep, method: "PATCH", body: body, decodeAs: T.self)
    }

    func delete(_ ep: Endpoint) async throws {
        _ = try await request(ep, method: "DELETE", body: Empty?.none, decodeAs: Empty.self)
    }

    @discardableResult
    func upload<T: Decodable>(
        _ ep: Endpoint,
        fileField: String,
        filename: String,
        mimeType: String,
        data: Data,
        fields: [String: String] = [:],
        as: T.Type = T.self
    ) async throws
        -> T
    {
        let boundary = "Boundary-\(UUID().uuidString)"
        var req = try await buildRequest(ep, method: "POST", body: Empty?.none, retryingAfter401: false)
        req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        req.httpBody = Self.multipartBody(
            boundary: boundary,
            fields: fields,
            fileField: fileField,
            filename: filename,
            mimeType: mimeType,
            data: data
        )
        return try await execute(req, ep: ep, method: "POST", body: Empty?.none, decodeAs: T.self)
    }

    /// Best-effort POST. Used for analytics where dropping events is
    /// preferable to UI lag or surfacing errors.
    func fireAndForget(_ ep: Endpoint, body: some Encodable & Sendable) async {
        do {
            _ = try await request(ep, method: "POST", body: body, decodeAs: Empty.self)
        } catch {
            log
                .info(
                    "fireAndForget \(ep.path, privacy: .public) dropped: \(error.localizedDescription, privacy: .public)"
                )
        }
    }

    // MARK: - Core

    private func request<T: Decodable>(
        _ ep: Endpoint,
        method: String,
        body: (some Encodable)?,
        decodeAs: T.Type
    ) async throws
        -> T
    {
        let req = try await buildRequest(ep, method: method, body: body, retryingAfter401: false)
        return try await execute(req, ep: ep, method: method, body: body, decodeAs: T.self)
    }

    private func buildRequest(
        _ ep: Endpoint,
        method: String,
        body: (some Encodable)?,
        retryingAfter401: Bool
    ) async throws
        -> URLRequest
    {
        var components = URLComponents(
            url: baseURL.appendingPathComponent(ep.path),
            resolvingAgainstBaseURL: false
        )
        if !ep.queryItems.isEmpty {
            components?.queryItems = ep.queryItems
        }
        guard let url = components?.url else { throw APIError.missingBaseURL }

        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.timeoutInterval = ep.timeout
        req.cachePolicy = ep.cachePolicy

        if !ep.isPublic {
            let token = try await auth.validAccessToken()
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        if let body, !(body is Empty) {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try encoder.encode(body)
        }

        return req
    }

    private func execute<T: Decodable>(
        _ req: URLRequest,
        ep: Endpoint,
        method: String,
        body: (some Encodable)?,
        decodeAs: T.Type
    ) async throws
        -> T
    {
        log.info("\(method, privacy: .public) \(ep.path, privacy: .public)")
        let data: Data
        let resp: URLResponse
        do {
            (data, resp) = try await urlSession.data(for: req)
        } catch {
            throw APIError.transport(error)
        }

        // One-shot 401 retry. supabase-swift refreshes the session as a
        // side effect of validAccessToken(), so re-fetching the token
        // post-refresh is enough.
        if let http = resp as? HTTPURLResponse, http.statusCode == 401, !ep.isPublic {
            log.info("401 on \(ep.path, privacy: .public) — retrying once with refreshed token")
            let retryReq = try await buildRequest(ep, method: method, body: body, retryingAfter401: true)
            let (retryData, retryResp): (Data, URLResponse)
            do {
                (retryData, retryResp) = try await urlSession.data(for: retryReq)
            } catch {
                throw APIError.transport(error)
            }
            try APIError.check(retryResp, data: retryData)
            return try decode(retryData, as: T.self)
        }

        try APIError.check(resp, data: data)
        return try decode(data, as: T.self)
    }

    private func decode<T: Decodable>(_ data: Data, as: T.Type) throws -> T {
        if T.self == Empty.self {
            // swiftlint:disable:next force_cast
            return Empty() as! T
        }
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            log.error("decode failed: \(error.localizedDescription, privacy: .public)")
            throw APIError.decoding(error)
        }
    }

    private static func multipartBody(
        boundary: String,
        fields: [String: String],
        fileField: String,
        filename: String,
        mimeType: String,
        data: Data
    ) -> Data {
        var body = Data()
        let lineBreak = "\r\n"
        for (name, value) in fields {
            body.appendString("--\(boundary)\(lineBreak)")
            body.appendString("Content-Disposition: form-data; name=\"\(name)\"\(lineBreak)\(lineBreak)")
            body.appendString("\(value)\(lineBreak)")
        }
        body.appendString("--\(boundary)\(lineBreak)")
        body.appendString(
            "Content-Disposition: form-data; name=\"\(fileField)\"; filename=\"\(filename)\"\(lineBreak)"
        )
        body.appendString("Content-Type: \(mimeType)\(lineBreak)\(lineBreak)")
        body.append(data)
        body.appendString(lineBreak)
        body.appendString("--\(boundary)--\(lineBreak)")
        return body
    }
}

/// Stand-in for endpoints that take no body or return no body.
struct Empty: Codable {}

private extension Data {
    mutating func appendString(_ string: String) {
        if let data = string.data(using: .utf8) {
            self.append(data)
        }
    }
}

extension APIClient {
    /// URLSession with a disk-backed URLCache so public GETs survive an
    /// app relaunch. Server-set Cache-Control / ETag headers drive
    /// freshness; per-endpoint cachePolicy decides whether to consult it.
    static func makeCachingSession() -> URLSession {
        let cfg = URLSessionConfiguration.default
        cfg.requestCachePolicy = .useProtocolCachePolicy
        cfg.urlCache = URLCache(
            memoryCapacity: 16 * 1024 * 1024,
            diskCapacity: 128 * 1024 * 1024,
            directory: nil
        )
        // Upper bound for the session; per-request `timeoutInterval` (Endpoint.timeout)
        // still caps each call, so normal requests keep their short deadline while
        // the slow AI endpoints (vision / enrich) are allowed to run longer.
        cfg.timeoutIntervalForRequest = 60
        return URLSession(configuration: cfg)
    }
}
