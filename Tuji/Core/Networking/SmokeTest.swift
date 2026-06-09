// One-shot smoke test against the backend's /api/test_smoke/whoami endpoint.
// Used by ContentView during W1 first-build verification. Will be deleted
// (along with the server endpoint) once iOS APIClient is verified against
// /api/users/me.
//
// no_hardcoded_base_url lint rule allows hardcoded URLs only inside
// Core/Networking/, which is exactly here.

import Foundation
import OSLog

enum SmokeTest {
    private static let log = Logger(subsystem: "app.tuji.ios", category: "smoke")

    private static let baseURL: URL = {
        if let str = Bundle.main.object(forInfoDictionaryKey: "TUJI_BASE_URL") as? String,
           let url = URL(string: str) {
            return url
        }
        // Fallback: production deployment. Replace once Info.plist injection
        // (INFOPLIST_FILE = Tuji/Info.plist) is wired in §6 polish.
        return URL(string: "https://everyday-english-picture-dictionary.vercel.app")!
    }()

    struct Result {
        let status: Int
        let body: String
    }

    static func whoami(bearer: String? = nil) async -> Result {
        let url = baseURL.appendingPathComponent("api/test_smoke/whoami")
        var req = URLRequest(url: url)
        req.timeoutInterval = 10
        if let bearer { req.setValue("Bearer \(bearer)", forHTTPHeaderField: "Authorization") }

        log.info("GET \(url.absoluteString, privacy: .public)")
        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
            let body = String(data: data, encoding: .utf8) ?? "(non-utf8 \(data.count)B)"
            log.info("status=\(code) body=\(body, privacy: .public)")
            return Result(status: code, body: body)
        } catch {
            log.error("err=\(error.localizedDescription, privacy: .public)")
            return Result(status: -1, body: "Error: \(error.localizedDescription)")
        }
    }
}
