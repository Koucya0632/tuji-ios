// 公開作者身分 — what the community sees when this user publishes.
//
// Separate from `ProfileUpdatePayload` (which edits the in-app greeting) even
// though both end up in `profiles`. The difference is consent, not storage:
// until `confirmed` is true the server refuses to publish anything under this
// account, and every public endpoint serializes the author as anonymous.

import Foundation

/// GET /api/users/public-author — current identity plus whether it was accepted.
struct PublicAuthorIdentity: Decodable, Hashable, Identifiable {
    let confirmed: Bool
    /// Public handle (`profiles.username`). Pre-filled into the setup screen as
    /// a suggestion; for accounts that never chose one it is a random
    /// `tuji-…` value, never anything derived from the email.
    let handle: String
    /// Empty when the user never set a display name.
    let displayName: String
    let avatar: String

    /// Handles are unique, so they identify the sheet's presentation state.
    var id: String {
        self.handle
    }
}

/// POST /api/users/public-author — accept (or later edit) the public identity.
struct PublicAuthorIdentityPayload: Encodable {
    let handle: String
    let displayName: String
    let avatar: String?
}

struct PublicAuthorIdentityResponse: Decodable {
    let ok: Bool?
    let confirmed: Bool?
    let handle: String?
    let displayName: String?
}
