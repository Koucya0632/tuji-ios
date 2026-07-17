import Foundation

/// Raw values are the API contract — they must match the backend whitelist in
/// app/api/users/feedback/route.ts and the feedback_type CHECK in migrate.ts.
enum FeedbackType: String, CaseIterable, Identifiable {
    case feature
    case bug
    case content
    case other

    var id: String {
        self.rawValue
    }
}

nonisolated struct FeedbackPayload: Encodable {
    let requestId: String
    let feedbackType: String
    let description: String
    let platform: String
    let appVersion: String
    let uiLang: String
}
