#if DEBUG
import Foundation
import Testing
@testable import Tuji

@MainActor
struct RegionalReadDiagnosticsTests {
    @Test func aggregatesAllDirectionsWithoutPersonalFields() async {
        var seen: [String] = []
        let rows = await RegionalReadDiagnostics.run(read: { endpoint in
            switch endpoint {
            case let .studyQueue(mode, _, _, _, _, learning):
                seen.append("\(learning)-\(mode)")
                return (200, "private, no-store", Data(#"{"queue":[{"word":{"id":"rental-bond","word":"private"}},{"word":{"id":"other"}}]}"#.utf8))
            case let .usersWordLists(learning, _):
                seen.append("\(learning)-lists")
                return (200, "private, no-store", Data(#"{"available":true,"lists":[{"id":"11111111-1111-4111-8111-111111111111","name":"private"}]}"#.utf8))
            case .usersWordList:
                return (200, "private, no-store", Data(#"{"wordIds":["rental-bond","other"]}"#.utf8))
            default: throw URLError(.badURL)
            }
        }, sameAccount: { true })
        #expect(RegionalReadDiagnostics.reservedCount == 19)
        #expect(seen == ["zh-en-new", "zh-en-review", "zh-en-lists", "zh-ja-new", "zh-ja-review", "zh-ja-lists"])
        #expect(rows.count == 6)
        #expect(rows.map(\.hits) == [1, 1, 1, 1, 1, 1])
        #expect(rows[0].count == 2 && rows[2].count == 1)
        #expect(rows.allSatisfy { $0.noStore == "是" })
        #expect(!String(describing: rows).contains("private"))
    }

    @Test func emptyUnavailableAndFailedDetailsAreNotPasses() async {
        var listReads = 0
        let rows = await RegionalReadDiagnostics.run(read: { endpoint in
            switch endpoint {
            case .studyQueue: return (200, "max-age=60", Data(#"{"queue":[]}"#.utf8))
            case .usersWordLists:
                listReads += 1
                return listReads == 1
                    ? (200, "no-store", Data(#"{"available":true,"lists":[]}"#.utf8))
                    : (200, "no-store", Data(#"{"available":true,"lists":[{"id":"11111111-1111-4111-8111-111111111111"}]}"#.utf8))
            case .usersWordList: return (403, nil, Data())
            default: throw URLError(.badURL)
            }
        }, sameAccount: { true })
        #expect(rows[0].noStore == "否")
        #expect(rows[2].hits == nil && rows[2].coverage.contains("沒有詞表"))
        #expect(rows[5].hits == nil && rows[5].coverage.contains("不完整"))
        #expect(rows[5].noStore == "否")
    }

    @Test func existingEmptyListHasUnknownHits() async {
        let rows = await RegionalReadDiagnostics.run(read: { endpoint in
            switch endpoint {
            case .studyQueue: return (200, "no-store", Data(#"{"queue":[]}"#.utf8))
            case .usersWordLists: return (200, "no-store", Data(#"{"available":true,"lists":[{"id":"11111111-1111-4111-8111-111111111111"}]}"#.utf8))
            case .usersWordList: return (200, "no-store", Data(#"{"wordIds":[]}"#.utf8))
            default: throw URLError(.badURL)
            }
        }, sameAccount: { true })
        #expect(rows[2].hits == nil && rows[2].coverage.contains("沒有詞條"))
        #expect(rows[5].hits == nil && rows[5].coverage.contains("沒有詞條"))
    }

    @Test func accountGenerationDetectsRapidABA() {
        let a = UUID(), b = UUID()
        let first = DiagnosticAccountGeneration.next(previous: nil, current: a, generation: 0)
        let second = DiagnosticAccountGeneration.next(previous: a, current: b, generation: first)
        let third = DiagnosticAccountGeneration.next(previous: b, current: a, generation: second)
        #expect(first == 1 && second == 2 && third == 3)
        #expect(DiagnosticAccountGeneration.next(previous: a, current: a, generation: third) == third)
        #expect(DiagnosticAccountGeneration.next(previous: a, current: nil, generation: third) == 4)
    }

    @Test func changingAccountDiscardsEverything() async {
        var checks = 0
        let rows = await RegionalReadDiagnostics.run(read: { _ in
            (200, "no-store", Data(#"{"queue":[]}"#.utf8))
        }, sameAccount: { checks += 1; return checks < 4 })
        #expect(rows.isEmpty)
    }

    @Test func guardMustMatchFormalSnapshotAndReservedIDs() throws {
        #expect(RegionalReadDiagnostics.reservedHash == "2a5dafc31da7c1f3ff27682d1460523d05d656dc333aa6b289d3ae9b3eaa57ae")
        let json = #"{"guardProtocol":"tuji-australia-catalogue-v2","deploymentCommit":"2f060cb3b9830d951ad391a75f81e1512da6fe5e","deploymentCommitSource":"vercel-environment-self-reported","reservedIdCount":19,"reservedIdsSha256":"2a5dafc31da7c1f3ff27682d1460523d05d656dc333aa6b289d3ae9b3eaa57ae","configurationSha256":"0db9dbe928c3f06fe0a43a01a52de9ce0aecef351aafd8038ad844272a6916af"}"#
        let data = Data(json.utf8)
        #expect(RegionalReadDiagnostics.verifiedGuard((200, "no-store", data)) != nil)
        #expect(RegionalReadDiagnostics.verifiedGuard((200, nil, data)) == nil)
        #expect(RegionalReadDiagnostics.verifiedGuard((500, "no-store", data)) == nil)
        #expect(RegionalReadDiagnostics.verifiedGuard((200, "no-store", Data(json.replacingOccurrences(of: "2f060cb3", with: "00000000").utf8))) == nil)
        #expect(RegionalReadDiagnostics.verifiedGuard((200, "no-store", Data(json.replacingOccurrences(of: "2a5dafc3", with: "00000000").utf8))) == nil)
    }

    @Test func missingNoStoreNeverParsesPayload() async {
        let rows = await RegionalReadDiagnostics.run(read: { _ in
            // Deliberately malformed JSON: refusal must happen before parsing.
            (200, "public, max-age=300", Data("private invalid data".utf8))
        }, sameAccount: { true })
        #expect(rows.count == 6)
        #expect(rows.allSatisfy { $0.noStore == "否" && $0.count == nil && $0.hits == nil && $0.coverage.contains("未解析") })
    }

    @Test func cacheDirectiveRequiresExactToken() {
        #expect(RegionalReadDiagnostics.noStore("private, No-Store"))
        #expect(!RegionalReadDiagnostics.noStore("private, no-store-extra"))
        #expect(!RegionalReadDiagnostics.noStore(nil))
    }
}

@MainActor
private final class DiagnosticFakeAuth: AccessTokenProviding {
    let isSignedIn = true
    func validAccessToken() async throws -> String { "synthetic-only" }
    func refreshedAccessToken(rejected: String?) async throws -> String { "synthetic-only" }
}

private final class DiagnosticProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var requestSeen: URLRequest?
    private static let lock = NSLock()
    static func take() -> URLRequest? { lock.withLock { defer { requestSeen = nil }; return requestSeen } }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.lock.withLock { Self.requestSeen = request }
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil,
                                       headerFields: ["Cache-Control": "private, no-store"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(#"{"queue":[]}"#.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

@MainActor
struct RegionalReadTransportTests {
    @Test func authenticatedGetAndEndpointAllowlist() async throws {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [DiagnosticProtocol.self]
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel() }
        let api = APIClient(auth: DiagnosticFakeAuth(), baseURL: URL(string: "https://tuji.nexflow.team")!)
        let result = try await api.diagnosticRead(.studyQueue(mode: "review", limit: 100, new: 100,
                                                              categories: [], lang: "zh-Hant", learning: "zh-en"), session: session)
        #expect(result.0 == 200 && RegionalReadDiagnostics.noStore(result.1))
        let request = try #require(DiagnosticProtocol.take())
        #expect(request.httpMethod == "GET")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer synthetic-only")
        #expect(request.value(forHTTPHeaderField: "Cache-Control") == "no-store")
        #expect(request.cachePolicy == .reloadIgnoringLocalCacheData)
        _ = try await api.diagnosticGuard(session: session)
        let guardRequest = try #require(DiagnosticProtocol.take())
        #expect(guardRequest.httpMethod == "GET")
        #expect(guardRequest.value(forHTTPHeaderField: "Authorization") == nil)
        #expect(guardRequest.url?.path == "/api/catalogue/region-guard")
        let wrongOrigin = APIClient(auth: DiagnosticFakeAuth(), baseURL: URL(string: "https://synthetic.invalid")!)
        #expect(wrongOrigin.diagnosticOrigin == nil)
        do { _ = try await wrongOrigin.diagnosticRead(.usersWordLists(learning: "zh-en", word: nil), session: session); Issue.record("unexpected origin accepted") } catch { }
        #expect(DiagnosticProtocol.take() == nil)
        do {
            _ = try await api.diagnosticRead(.studyAnswer, session: session)
            Issue.record("disallowed endpoint accepted")
        } catch { }
        #expect(DiagnosticProtocol.take() == nil)
    }
}
#endif
