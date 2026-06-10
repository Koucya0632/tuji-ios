// Response model for GET /api/test_smoke/whoami.
//
// Backend reply shape (camelCase already):
//   { "userId": String | null, "source": "none"|"bearer"|"cookie",
//     "headerWasSet": Bool }
//
// Delete this alongside SmokeTest once W2 finishes verifying the Bearer
// chain through the typed APIClient.

import Foundation

struct WhoamiResponse: Decodable {
    let userId: String?
    let source: Source
    let headerWasSet: Bool

    enum Source: String, Decodable {
        case none, bearer, cookie
    }
}
