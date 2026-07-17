// Anonymous product analytics → POST /api/events (public, fire-and-forget).
// Events carry NO user identity; the session id is a fresh UUID per app
// launch, deliberately not persistent — real DAU comes from study_logs
// server-side, so a durable device id would add privacy surface for
// nothing. Server-derived metrics (answers, favorites, purchases) are
// never duplicated as events.

import Foundation
import OSLog

/// Raw values are the API contract — they must match VALID_TYPES in
/// tuji-web app/api/events/route.ts.
enum AnalyticsEvent: String, CaseIterable {
    case view
    case pronounce
    case appOpen = "app_open"
    case studyStart = "study_start"
    case studyComplete = "study_complete"
    case paywallView = "paywall_view"
    case shareApp = "share_app"
    case atlasCaptureOpen = "atlas_capture_open"
}

@MainActor
final class AnalyticsService {
    static let shared = AnalyticsService()

    private let api: APIClient
    private let sessionId = UUID().uuidString
    private let log = Logger(subsystem: "app.tuji.ios", category: "analytics")

    init(api: APIClient = .shared) {
        self.api = api
    }

    /// Fire-and-forget; never blocks or throws. Suppressed in TUJI_DEV
    /// because Debug builds point TUJI_BASE_URL at production — dev taps
    /// would pollute the real dashboard.
    func track(_ event: AnalyticsEvent, wordId: String? = nil, category: String? = nil) {
        #if TUJI_DEV
        self.log.debug("suppressed \(event.rawValue, privacy: .public)")
        #else
        let payload = EventPayload(
            type: event.rawValue,
            wordId: wordId,
            category: category,
            sessionId: self.sessionId,
            platform: "ios"
        )
        Task { await self.api.fireAndForget(.events, body: payload) }
        #endif
    }
}

/// nonisolated so Encodable conformance escapes MainActor isolation;
/// needed because APIClient.fireAndForget requires Body: Sendable.
// swiftformat:disable:next redundantSendable
nonisolated struct EventPayload: Encodable, Sendable {
    let type: String
    let wordId: String?
    let category: String?
    let sessionId: String
    let platform: String
}
