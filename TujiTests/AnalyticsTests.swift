// AnalyticsEvent raw values and EventPayload keys are the wire contract
// with tuji-web (VALID_TYPES in app/api/events/route.ts) — these tests pin
// them so a rename on either side breaks CI instead of events silently
// 400ing in production.

import Foundation
import Testing
@testable import Tuji

struct AnalyticsTests {
    @Test
    func eventRawValuesMatchBackendWhitelist() {
        #expect(AnalyticsEvent.allCases.map(\.rawValue) == [
            "view", "pronounce", "app_open", "study_start",
            "study_complete", "paywall_view", "share_app", "atlas_capture_open"
        ])
    }

    @Test
    func payloadEncodesBackendFieldNames() throws {
        let payload = EventPayload(
            type: "view",
            wordId: "apple",
            category: "fruit",
            sessionId: "00000000-0000-4000-8000-000000000000",
            platform: "ios"
        )
        let data = try JSONEncoder().encode(payload)
        let json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(
            json.keys.sorted() == ["category", "platform", "sessionId", "type", "wordId"]
        )
    }
}
