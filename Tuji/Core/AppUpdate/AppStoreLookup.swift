// App Store 上「現在上架的是哪一版」，從 Apple 自己的 lookup API 讀。
//
// 為什麼不是後端給：因為那會多出一個要記得更新的地方。版本號寫在
// `Config/Version.xcconfig`，送審通過後 App Store 就是它自己的真相來源 ——
// 中間再插一個 `/api/config` 的 `latest_version`，就等於每次發版都要記得
// 去改第二個數字，而「忘記改第二個地方」是這個 repo 最常見的缺陷形狀。
//
// 代價是 Apple 的 CDN 會晚幾個小時才反映新版本。對一個「有空再更新」的提示
// 來說，晚幾個小時沒有任何影響。
//
// 這條路上所有的失敗都是安靜的：查不到、解不開、沒網路，都當作「沒有新版」。
// 一個更新提示不值得為它跳任何一個錯誤畫面。

import Foundation
import OSLog

/// App Store 上那一版：版本號，以及它自己的商店頁網址。
///
/// 網址是 Apple 回傳的 `trackViewUrl`，不是我們拼的 —— 拼一個網址就要在程式碼裡
/// 寫死 app id 和地區，而這裡本來就有一個正確的。
struct AppStoreRelease: Equatable {
    let version: String
    let url: URL
}

protocol AppStoreVersionLookup: Sendable {
    /// 查不到就回 `nil`。丟不丟 error 由實作決定，呼叫端兩種都當作「沒有新版」。
    func latestRelease() async throws -> AppStoreRelease?
}

struct LiveAppStoreLookup: AppStoreVersionLookup {
    /// 上架的那個 bundle id，寫死。
    ///
    /// 不讀 `Bundle.main.bundleIdentifier`：Debug 版是 `app.tuji.ios.debug`，
    /// 查詢會回 0 筆，於是這整條路在開發時永遠測不到 —— 唯一會執行到它的環境
    /// 就是使用者的手機。
    static let releaseBundleID = "app.tuji.ios"

    private let urlSession: URLSession
    private let log = Logger(subsystem: "app.tuji.ios", category: "app-update")

    init(urlSession: URLSession = .shared) {
        self.urlSession = urlSession
    }

    func latestRelease() async throws -> AppStoreRelease? {
        guard let url = URL(
            string: "https://itunes.apple.com/lookup?bundleId=\(Self.releaseBundleID)"
        )
        else { return nil }

        var request = URLRequest(url: url)
        // 這個回應本來就會被 Apple 的 CDN 快取，不需要在裝置上再存一份舊的。
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 10

        let (data, response) = try await self.urlSession.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            return nil
        }

        let payload = try JSONDecoder().decode(LookupResponse.self, from: data)
        // 沒有結果不是錯誤：App 還沒上架、或這個地區沒有，都會走到這裡。
        guard let result = payload.results.first else {
            self.log.debug("App Store lookup returned no results")
            return nil
        }
        guard let storeURL = URL(string: result.trackViewUrl) else { return nil }
        return AppStoreRelease(version: result.version, url: storeURL)
    }

    private struct LookupResponse: Decodable {
        let results: [Result]

        struct Result: Decodable {
            let version: String
            let trackViewUrl: String
        }
    }
}
