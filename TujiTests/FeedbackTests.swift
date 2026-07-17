// FeedbackType raw values and FeedbackPayload keys are the wire contract with
// tuji-web (app/api/users/feedback/route.ts whitelist + the feedback_type
// CHECK in scripts/migrate.ts) — these tests pin them so a rename on either
// side breaks CI instead of silently 400ing in production.

import Foundation
import Testing
@testable import Tuji

struct FeedbackTests {
    @Test
    func typeRawValuesMatchBackendWhitelist() {
        #expect(FeedbackType.allCases.map(\.rawValue) == ["feature", "bug", "content", "other"])
    }

    @Test
    func payloadEncodesBackendFieldNames() throws {
        let payload = FeedbackPayload(
            requestId: "00000000-0000-4000-8000-000000000000",
            feedbackType: "feature",
            description: "test",
            platform: "ios",
            appVersion: "1.0 (1)",
            uiLang: "zh-Hant"
        )
        let data = try JSONEncoder().encode(payload)
        let json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(
            json.keys.sorted() == [
                "appVersion", "description", "feedbackType",
                "platform", "requestId", "uiLang"
            ]
        )
    }
}
