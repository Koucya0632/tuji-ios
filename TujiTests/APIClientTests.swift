// The first tests the HTTP layer has ever had.
//
// Everything used to be faked at the repository role seam, one level *above*
// the transport — so auth attachment, the one-shot 401 retry and the multipart
// upload were never exercised. A `URLProtocol` stub was already possible
// (`urlSession` was injectable), but it could only reach the 11 public
// endpoints: the other 50 went through `AuthService.validAccessToken()` first,
// and `AuthService.init` is `private` with a `fatalError`ing dependency.
//
// With `AccessTokenProviding` in place the whole surface is reachable. The
// first test below is the regression the multipart-retry fix shipped without,
// because at the time there was nowhere to put it.

import Foundation
import Testing
@testable import Tuji

@MainActor
struct APIClientTests {
    private struct Ack: Decodable { let ok: Bool? }

    private func client(
        auth: any AccessTokenProviding = FakeAuth(),
        handler: @escaping @Sendable (URLRequest) -> StubResponse
    )
        -> APIClient
    {
        let key = StubRegistry.register(handler)
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        config.httpAdditionalHeaders = [StubURLProtocol.headerKey: key]
        return APIClient(
            auth: auth,
            urlSession: URLSession(configuration: config),
            baseURL: URL(string: "https://stub.invalid")!
        )
    }

    // MARK: - The regression the fix shipped without

    @Test("a 401-retried upload still carries its multipart body")
    func retriedUploadKeepsItsBody() async throws {
        // The bug: `upload` attached the body *after* buildRequest, then the
        // 401 retry rebuilt the request from the original (empty) body — so the
        // retried photo upload went out with nothing in it.
        let recorder = RequestRecorder()
        let api = self.client { request in
            let isRetry = recorder.record(request)
            return isRetry
                ? StubResponse(status: 200, body: #"{"ok":true}"#)
                : StubResponse(status: 401, body: "")
        }

        _ = try await api.upload(
            .atlasImages(limit: 1),
            fileField: "file",
            filename: "photo.jpg",
            mimeType: "image/jpeg",
            data: Data(repeating: 0xAB, count: 32),
            as: Ack.self
        )

        #expect(recorder.count == 2, "the 401 must be retried exactly once")
        let retried = try #require(recorder.last)
        #expect(retried.bodyByteCount > 32, "the retried upload lost its multipart body")
        #expect(
            retried.contentType?.hasPrefix("multipart/form-data") == true,
            "the retried upload lost its multipart content type"
        )
    }

    @Test("a per-call cache policy survives the 401 retry")
    func retryKeepsTheCachePolicyOverride() async throws {
        let recorder = RequestRecorder()
        let api = self.client { request in
            let isRetry = recorder.record(request)
            return isRetry
                ? StubResponse(status: 200, body: #"{"ok":true}"#)
                : StubResponse(status: 401, body: "")
        }

        _ = try await api.get(
            .usersMe,
            as: Ack.self,
            cachePolicy: .reloadIgnoringLocalCacheData
        )

        let retried = try #require(recorder.last)
        #expect(retried.cachePolicy == .reloadIgnoringLocalCacheData)
    }

    @Test("the retry carries a freshly fetched token")
    func retryRefreshesTheToken() async throws {
        let auth = FakeAuth(tokens: ["stale", "fresh"])
        let recorder = RequestRecorder()
        let api = self.client(auth: auth) { request in
            let isRetry = recorder.record(request)
            return isRetry
                ? StubResponse(status: 200, body: #"{"ok":true}"#)
                : StubResponse(status: 401, body: "")
        }

        _ = try await api.get(.usersMe, as: Ack.self)

        #expect(recorder.authorizations == ["Bearer stale", "Bearer fresh"])
    }

    @Test("a public endpoint's 401 is not retried")
    func publicEndpointsAreNotRetried() async {
        // The retry exists to recover a stale session. A public endpoint has no
        // session to refresh, so retrying would just double the failure.
        let recorder = RequestRecorder()
        let api = self.client { request in
            _ = recorder.record(request)
            return StubResponse(status: 401, body: "")
        }

        _ = try? await api.get(.categories(lang: "zh-Hant"), as: Ack.self)

        #expect(recorder.count == 1)
    }

    // MARK: - Auth attachment

    @Test("a private endpoint always carries a bearer token")
    func privateEndpointsCarryABearer() async throws {
        let recorder = RequestRecorder()
        let api = self.client { request in
            _ = recorder.record(request)
            return StubResponse(status: 200, body: #"{"ok":true}"#)
        }

        _ = try await api.get(.usersMe, as: Ack.self)

        #expect(recorder.last?.authorization == "Bearer stale")
    }

    @Test("a public endpoint carries no token at all")
    func publicEndpointsCarryNothing() async throws {
        let recorder = RequestRecorder()
        let api = self.client { request in
            _ = recorder.record(request)
            return StubResponse(status: 200, body: #"{"ok":true}"#)
        }

        _ = try await api.get(.categories(lang: "zh-Hant"), as: Ack.self)

        #expect(recorder.last?.authorization == nil)
    }

    @Test("an optional-auth endpoint attaches a token only when signed in")
    func optionalAuthFollowsTheSession() async throws {
        let signedOut = RequestRecorder()
        let guestApi = self.client(auth: FakeAuth(isSignedIn: false)) { request in
            _ = signedOut.record(request)
            return StubResponse(status: 200, body: #"{"ok":true}"#)
        }
        _ = try await guestApi.get(.atlasPublicCollection(slug: "s"), as: Ack.self)
        #expect(signedOut.last?.authorization == nil, "a guest must still be able to read it")

        let signedIn = RequestRecorder()
        let userApi = self.client(auth: FakeAuth(isSignedIn: true)) { request in
            _ = signedIn.record(request)
            return StubResponse(status: 200, body: #"{"ok":true}"#)
        }
        _ = try await userApi.get(.atlasPublicCollection(slug: "s"), as: Ack.self)
        #expect(signedIn.last?.authorization == "Bearer stale")
    }

    @Test("a private request without a session fails before it is sent")
    func missingSessionFailsClosed() async {
        let recorder = RequestRecorder()
        let api = self.client(auth: FakeAuth(tokens: [])) { request in
            _ = recorder.record(request)
            return StubResponse(status: 200, body: #"{"ok":true}"#)
        }

        _ = try? await api.get(.usersMe, as: Ack.self)

        #expect(recorder.requests.isEmpty, "an unauthenticated private call must not reach the network")
    }

    // MARK: - Status mapping

    @Test("402 becomes a paywall error carrying the server's message")
    func paymentRequiredKeepsItsMessage() async {
        let api = self.client { _ in
            StubResponse(status: 402, body: #"{"error":"升級 Pro 可擴充"}"#)
        }

        await #expect(throws: APIError.self) {
            _ = try await api.get(.atlasEntitlement, as: Ack.self)
        }
    }

    /// Two different answers share status 429. `save_limit` is the 收進容量
    /// ceiling (CONTEXT.md) and the advice it needs is the opposite of a
    /// throttle's: waiting never clears it, removing something does. The body's
    /// `error` is what tells them apart — the status code cannot be changed
    /// without every shipped client rendering 「伺服器出了點問題（409）」.
    @Test("a 429 save_limit is a capacity ceiling, not a throttle")
    func saveLimitIsToldApartFromAThrottle() async {
        let api = self.client { _ in
            StubResponse(
                status: 429,
                body: #"{"error":"save_limit","message":"學習項目已達上限（1000），移除一些後再加入。","limit":1000,"usage":1000}"#
            )
        }

        guard case let .atCapacity(limit, usage)? = await self.thrownAPIError({
            _ = try await api.get(.atlasEntitlement, as: Ack.self)
        })
        else {
            Issue.record("expected .atCapacity")
            return
        }
        #expect(limit == 1000)
        #expect(usage == 1000)
    }

    /// Everything else on 429 is a genuine throttle and keeps the server's copy
    /// — that is where the atlas daily-AI cap's product text comes from.
    @Test("every other 429 stays a throttle")
    func aPlainRateLimitIsUnchanged() async {
        let api = self.client { _ in
            StubResponse(status: 429, body: #"{"error":"rate_limited","message":"操作過於頻繁"}"#)
        }

        guard case let .rateLimited(message)? = await self.thrownAPIError({
            _ = try await api.get(.atlasEntitlement, as: Ack.self)
        })
        else {
            Issue.record("expected .rateLimited")
            return
        }
        #expect(message == "操作過於頻繁")
    }

    /// A ceiling with no numbers on it still has to produce a sentence, so the
    /// parse is optional all the way down rather than a precondition.
    @Test("a save_limit body without numbers is still a ceiling")
    func saveLimitSurvivesAMissingLimit() async {
        let api = self.client { _ in
            StubResponse(status: 429, body: #"{"error":"save_limit"}"#)
        }

        guard case let .atCapacity(limit, usage)? = await self.thrownAPIError({
            _ = try await api.get(.atlasEntitlement, as: Ack.self)
        })
        else {
            Issue.record("expected .atCapacity")
            return
        }
        #expect(limit == nil)
        #expect(usage == nil)
    }

    /// Captures the `APIError` a call throws. Written once because three tests
    /// need to look *inside* the case, which `#expect(throws:)` cannot do.
    private func thrownAPIError(
        _ body: () async throws -> Void
    ) async
        -> APIError?
    {
        do {
            try await body()
            Issue.record("expected a throw")
            return nil
        } catch let error as APIError {
            return error
        } catch {
            Issue.record("expected an APIError, got \(error)")
            return nil
        }
    }

    @Test("the endpoint's query items reach the wire")
    func queryItemsAreSent() async throws {
        let recorder = RequestRecorder()
        let api = self.client { request in
            _ = recorder.record(request)
            return StubResponse(status: 200, body: #"{"ok":true}"#)
        }

        _ = try await api.get(.categories(lang: "ja"), as: Ack.self)

        #expect(recorder.last?.url?.query?.contains("lang=ja") == true)
    }

    /// `/api/search` is `.publicCached`, so its URL *is* its cache key. It used
    /// to carry only `q`, which gave both learning directions one entry —
    /// switching 學習語言 and repeating a search could be served the other
    /// language's rows straight out of URLCache.
    @Test("a search URL is distinct per learning direction")
    func searchCarriesTheDirectionInItsIdentity() async throws {
        let recorder = RequestRecorder()
        let api = self.client { request in
            _ = recorder.record(request)
            return StubResponse(status: 200, body: #"{"ok":true}"#)
        }

        _ = try await api.get(.search(q: "cup", lang: "zh-Hant", learning: "zh-en"), as: Ack.self)
        let english = recorder.last?.url
        _ = try await api.get(.search(q: "cup", lang: "zh-Hant", learning: "zh-ja"), as: Ack.self)
        let japanese = recorder.last?.url

        #expect(english != nil)
        #expect(english != japanese)
        #expect(japanese?.query?.contains("learning=zh-ja") == true)
    }

    @Test("the endpoint's timeout reaches the request")
    func timeoutIsApplied() async throws {
        let recorder = RequestRecorder()
        let api = self.client { request in
            _ = recorder.record(request)
            return StubResponse(status: 200, body: #"{"ok":true}"#)
        }

        _ = try await api.get(.atlasItemDetail(id: "x"), as: Ack.self)

        #expect(recorder.last?.timeout == 60, "the AI endpoints need the long timeout")
    }
}

// MARK: - Stubs

private struct StubResponse {
    let status: Int
    let body: String
}

/// One recorded request, flattened — `URLProtocol` strips `httpBody` into a
/// stream, so the byte count is captured at record time.
private struct RecordedRequest {
    let url: URL?
    let authorization: String?
    let contentType: String?
    let cachePolicy: URLRequest.CachePolicy
    let timeout: TimeInterval
    let bodyByteCount: Int
}

/// Thread-safe: `URLProtocol.startLoading` runs on a background thread, so this
/// cannot be `@MainActor`. (It was, briefly, with a `MainActor.assumeIsolated`
/// inside — which traps rather than hops, and took the whole test process down.)
private final class RequestRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [RecordedRequest] = []

    var requests: [RecordedRequest] {
        self.lock.withLock { self.storage }
    }

    var count: Int {
        self.requests.count
    }

    var last: RecordedRequest? {
        self.requests.last
    }

    var authorizations: [String] {
        self.requests.compactMap(\.authorization)
    }

    /// Returns true when this is a retry (i.e. something was already recorded).
    func record(_ request: URLRequest) -> Bool {
        let recorded = RecordedRequest(
            url: request.url,
            authorization: request.value(forHTTPHeaderField: "Authorization"),
            contentType: request.value(forHTTPHeaderField: "Content-Type"),
            cachePolicy: request.cachePolicy,
            timeout: request.timeoutInterval,
            bodyByteCount: RequestRecorder.byteCount(of: request)
        )
        return self.lock.withLock {
            let isRetry = !self.storage.isEmpty
            self.storage.append(recorded)
            return isRetry
        }
    }

    /// `URLProtocol` moves `httpBody` into `httpBodyStream`, so read whichever
    /// one survived.
    private static func byteCount(of request: URLRequest) -> Int {
        if let body = request.httpBody { return body.count }
        guard let stream = request.httpBodyStream else { return 0 }
        stream.open()
        defer { stream.close() }
        var total = 0
        var buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let read = stream.read(&buffer, maxLength: buffer.count)
            if read <= 0 { break }
            total += read
        }
        return total
    }
}

@MainActor
private final class FakeAuth: AccessTokenProviding {
    private var tokens: [String]
    let isSignedIn: Bool

    init(tokens: [String] = ["stale"], isSignedIn: Bool = true) {
        self.tokens = tokens
        self.isSignedIn = isSignedIn
    }

    func validAccessToken() async throws -> String {
        guard !self.tokens.isEmpty else { throw APIError.unauthorized }
        // Each ask yields the next token, so a test can assert the retry picked
        // up a refreshed one.
        return self.tokens.count == 1 ? self.tokens[0] : self.tokens.removeFirst()
    }
}

/// Handlers keyed by a per-client id carried on a request header, so suites
/// running in parallel cannot see each other's stub.
private enum StubRegistry {
    private nonisolated(unsafe) static var handlers: [String: @Sendable (URLRequest) -> StubResponse] = [:]
    private static let lock = NSLock()

    static func register(_ handler: @escaping @Sendable (URLRequest) -> StubResponse) -> String {
        let key = UUID().uuidString
        self.lock.withLock { self.handlers[key] = handler }
        return key
    }

    static func handler(for key: String) -> (@Sendable (URLRequest) -> StubResponse)? {
        self.lock.withLock { self.handlers[key] }
    }
}

private final class StubURLProtocol: URLProtocol, @unchecked Sendable {
    static let headerKey = "X-Tuji-Stub"

    override class func canInit(with request: URLRequest) -> Bool {
        request.value(forHTTPHeaderField: headerKey) != nil
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let key = request.value(forHTTPHeaderField: Self.headerKey),
              let handler = StubRegistry.handler(for: key),
              let url = request.url
        else {
            self.client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }
        let stub = handler(self.request)
        guard let response = HTTPURLResponse(
            url: url,
            statusCode: stub.status,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        )
        else {
            self.client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        self.client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        self.client?.urlProtocol(self, didLoad: Data(stub.body.utf8))
        self.client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
