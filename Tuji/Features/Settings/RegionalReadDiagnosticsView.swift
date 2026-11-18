#if DEBUG
import CryptoKit
import Foundation
import SwiftUI

// Snapshot of the published guard's reserved IDs. These are catalog IDs, not
// personal data. Do not display IDs, names, examples, list IDs, or response bodies.
private let reservedAustralianIDs: Set<String> = [
    "availability", "bills-included", "casual-employee", "condition-report", "orientation",
    "pay-slip", "payment-terminal", "proof-of-enrolment", "rental-bond", "roster",
    "share-house", "shift-handover", "student-portal", "student-services-desk", "superannuation",
    "tax-file-number", "tenancy-agreement", "trial-shift", "view-a-room"
]

struct RegionalReadSummary: Identifiable, Equatable {
    let id: String
    let status: String
    let noStore: String
    let count: Int?
    let hits: Int?
    let coverage: String
}

private struct QueueBody: Decodable {
    struct Item: Decodable { struct Word: Decodable { let id: String }; let word: Word }
    let queue: [Item]
}
private struct ListsBody: Decodable {
    struct List: Decodable { let id: String }
    let available: Bool
    let lists: [List]
}
private struct ListBody: Decodable { let wordIds: [String] }

// Redirects are not followed: never forward the signed-in request to an
// unexpected host. URLSession is ephemeral and has no URLCache or cookies.
private final class DiagnosticSessionDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest,
                    completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

struct RegionalGuard: Decodable, Equatable {
    let guardProtocol: String
    let deploymentCommit: String?
    let deploymentCommitSource: String
    let reservedIdCount: Int
    let reservedIdsSha256: String
    let configurationSha256: String
}

@MainActor
enum RegionalReadDiagnostics {
    typealias Reader = (Endpoint) async throws -> (Int, String?, Data)

    static var reservedCount: Int { reservedAustralianIDs.count }
    static let expectedCommit = "2f060cb3b9830d951ad391a75f81e1512da6fe5e"
    static let expectedConfiguration = "0db9dbe928c3f06fe0a43a01a52de9ce0aecef351aafd8038ad844272a6916af"
    static var reservedHash: String {
        let data = (try? JSONSerialization.data(withJSONObject: reservedAustralianIDs.sorted())) ?? Data()
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
    static func verifiedGuard(_ response: (Int, String?, Data)) -> RegionalGuard? {
        guard response.0 == 200, noStore(response.1),
              let guardInfo = try? JSONDecoder().decode(RegionalGuard.self, from: response.2),
              guardInfo.guardProtocol == "tuji-australia-catalogue-v2",
              guardInfo.deploymentCommitSource == "vercel-environment-self-reported",
              guardInfo.deploymentCommit == expectedCommit,
              guardInfo.configurationSha256 == expectedConfiguration,
              guardInfo.reservedIdCount == 19, reservedCount == 19,
              guardInfo.reservedIdsSha256 == reservedHash else { return nil }
        return guardInfo
    }
    static func noStore(_ header: String?) -> Bool {
        header?.split(separator: ",").contains { $0.trimmingCharacters(in: .whitespaces).lowercased() == "no-store" } == true
    }

    /// Counts only; the decoded IDs never escape into UI state. The caller's
    /// identity closure detects a changed account without revealing its value.
    static func run(read: Reader, sameAccount: () -> Bool) async -> [RegionalReadSummary] {
        var results: [RegionalReadSummary] = []
        for direction in ["zh-en", "zh-ja"] {
            for mode in ["new", "review", "lists"] {
                guard sameAccount() else { return [] }
                let label = "\(direction == "zh-en" ? "澳洲" : "日本")・\(mode == "new" ? "新學" : mode == "review" ? "複習" : "詞表")"
                var responseStatus: Int?
                var responseNoStore: Bool?
                do {
                    let endpoint: Endpoint = mode == "lists"
                        ? .usersWordLists(learning: direction, word: nil)
                        : .studyQueue(mode: mode, limit: 100, new: 100, categories: [], lang: "zh-Hant", learning: direction)
                    let (status, cache, data) = try await read(endpoint)
                    guard sameAccount() else { return [] }
                    var cacheOK = noStore(cache)
                    responseStatus = status
                    responseNoStore = cacheOK
                    guard status == 200 else {
                        results.append(.init(id: label, status: "HTTP \(status)", noStore: cacheOK ? "是" : "否",
                                             count: nil, hits: nil, coverage: "請求未成功"))
                        continue
                    }
                    guard cacheOK else {
                        results.append(.init(id: label, status: "HTTP \(status)；回應不可信", noStore: "否",
                                             count: nil, hits: nil, coverage: "缺少 no-store；未解析資料。"))
                        continue
                    }
                    if mode != "lists" {
                        let queue = try JSONDecoder().decode(QueueBody.self, from: data).queue
                        results.append(.init(id: label, status: "HTTP 200", noStore: cacheOK ? "是" : "否",
                                             count: queue.count, hits: queue.filter { reservedAustralianIDs.contains($0.word.id) }.count,
                                             coverage: "最多 100 筆的當前佇列，非完整圖鑑；空佇列不代表完整隔離。"))
                    } else {
                        let body = try JSONDecoder().decode(ListsBody.self, from: data)
                        guard body.available, !body.lists.isEmpty else {
                            results.append(.init(id: label, status: "HTTP 200", noStore: cacheOK ? "是" : "否",
                                                 count: body.lists.count, hits: nil,
                                                 coverage: body.available ? "沒有詞表，無法檢查詞條。" : "此帳號的詞表功能不可用，無法檢查詞條。"))
                            continue
                        }
                        var hits = 0
                        var words = 0
                        var completed = 0
                        var failed = false
                        var cacheUnknown = false
                        // Bound network work. If truncated or any detail fails, the
                        // UI reports partial coverage rather than a zero-hit pass.
                        for list in body.lists.prefix(50) {
                            guard sameAccount() else { return [] }
                            guard UUID(uuidString: list.id) != nil else { failed = true; cacheUnknown = true; continue }
                            do {
                                let (detailStatus, detailCache, detailData) = try await read(.usersWordList(id: list.id))
                                guard sameAccount() else { return [] }
                                cacheOK = cacheOK && noStore(detailCache)
                                guard detailStatus == 200, noStore(detailCache) else { failed = true; continue }
                                let ids = try JSONDecoder().decode(ListBody.self, from: detailData).wordIds
                                completed += 1
                                words += ids.count
                                hits += ids.filter { reservedAustralianIDs.contains($0) }.count
                            } catch { failed = true; cacheUnknown = true }
                        }
                        let partial = failed || completed != body.lists.count
                        results.append(.init(id: label, status: partial ? "HTTP 200；部分明細失敗或未檢查" : "HTTP 200",
                                             noStore: !cacheOK ? "否" : cacheUnknown ? "未知" : "是", count: body.lists.count,
                                             hits: words == 0 ? nil : hits,
                                             coverage: "已檢查 \(completed)/\(body.lists.count) 個詞表、\(words) 個詞條；最多檢查 50 個詞表。\(partial ? "結果不完整，無法驗證詞條隔離。" : words == 0 ? "沒有詞條，無法驗證詞條隔離。" : "只涵蓋目前帳號的詞表。")"))
                    }
                } catch {
                    guard sameAccount() else { return [] }
                    results.append(.init(id: label, status: responseStatus.map { "HTTP \($0)；資料格式錯誤" } ?? "連線錯誤",
                                         noStore: responseNoStore.map { $0 ? "是" : "否" } ?? "未知", count: nil,
                                         hits: nil, coverage: "未能完成檢查。"))
                }
            }
        }
        return results
    }

    static func makeSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.urlCache = nil
        config.httpCookieStorage = nil
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.timeoutIntervalForRequest = 20
        return URLSession(configuration: config, delegate: DiagnosticSessionDelegate(), delegateQueue: nil)
    }
}

struct RegionalReadDiagnosticsView: View {
    @Environment(AuthService.self) private var auth
    @State private var results: [RegionalReadSummary] = []
    @State private var busy = false
    @State private var message: String?
    @State private var accountEpoch = 0
    @State private var source: String?

    var body: some View {
        VStack(spacing: 0) {
            TujiNavBar(leading: .back)
            ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("日本／澳洲讀取檢查").font(.title2.bold())
                Text("僅開發版。使用目前登入的帳號，唯讀檢查；不顯示詞條、詞表名稱或登入憑證。")
                Button(busy ? "檢查中…" : "開始檢查") { Task { await run() } }
                    .disabled(busy)
                if let source { Text(source).font(.caption) }
                if let message { Text(message) }
                ForEach(results) { result in
                    VStack(alignment: .leading, spacing: 5) {
                        Text(result.id).font(.headline)
                        Text("狀態：\(result.status)　no-store：\(result.noStore)")
                        Text("結果數：\(result.count.map(String.init) ?? "未知")　19 個保留詞命中：\(result.hits.map(String.init) ?? "未知")")
                        Text(result.coverage).font(.caption)
                    }
                    .padding().frame(maxWidth: .infinity, alignment: .leading)
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
                }
            }.padding()
            }
        }
        .navigationTitle("開發診斷")
        .onChange(of: auth.session.signedInUser?.id) { _, _ in
            accountEpoch += 1
            results = []
            message = "帳號狀態已變更，結果已丟棄。"
        }
        .onDisappear { accountEpoch += 1 }
    }

    private func run() async {
        guard case let .signedIn(user) = auth.state else { message = "請先登入。"; return }
        let originalID = user.id
        let originalEpoch = accountEpoch
        let originalAuthEpoch = auth.diagnosticAccountEpoch
        results = []
        source = nil
        message = nil
        busy = true
        defer { busy = false }
        let session = RegionalReadDiagnostics.makeSession()
        defer { session.invalidateAndCancel() }
        let api = APIClient.shared
        guard let origin = api.diagnosticOrigin,
              let response = try? await api.diagnosticGuard(session: session),
              let before = RegionalReadDiagnostics.verifiedGuard(response) else {
            message = "正式站來源或 guard 版本不符，未執行帳號資料讀取。"
            return
        }
        let sameAccount = {
            if case let .signedIn(current) = auth.state {
                return current.id == originalID && accountEpoch == originalEpoch && auth.diagnosticAccountEpoch == originalAuthEpoch
            }
            return false
        }
        guard sameAccount() else { message = "帳號狀態已變更，結果已丟棄。"; return }
        let summaries = await RegionalReadDiagnostics.run(
            read: { try await api.diagnosticRead($0, session: session) }, sameAccount: sameAccount
        )
        guard sameAccount(), !summaries.isEmpty else { message = "帳號狀態已變更，結果已丟棄。"; return }
        guard let finalResponse = try? await api.diagnosticGuard(session: session),
              let after = RegionalReadDiagnostics.verifiedGuard(finalResponse), before == after,
              sameAccount() else {
            message = "檢查後來源、版本或帳號狀態未能確認，結果已丟棄。"
            return
        }
        source = "來源：\(origin)；部署：\(before.deploymentCommit ?? "未知")。版本由平台自報，不證明每次請求落在相同實例。"
        results = summaries
    }
}
#endif
