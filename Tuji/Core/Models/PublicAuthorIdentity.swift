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
    /// The public self-introduction as it stands today. Unlike `handle` and
    /// `displayName` this is not a suggestion awaiting consent — once written it
    /// is already on the author's page. Optional so a payload from a server that
    /// predates the field still decodes.
    let bio: String?
    /// Server-owned length limit, so the client's counter can't drift from the
    /// rule that actually rejects.
    let bioMax: Int?
    /// False while the rename cooldown is running. A rename rewrites the byline
    /// on everything the author ever published, so it is rate-limited once they
    /// have public content. Note this covers the handle and display name only —
    /// the bio is never frozen.
    let canChange: Bool?
    /// ISO timestamp when the next change becomes possible; nil when it already is.
    let nextChangeAt: String?

    /// Handles are unique, so they identify the sheet's presentation state.
    var id: String {
        self.handle
    }

    /// Editable unless the server explicitly says otherwise, so a payload
    /// without the field never locks someone out of their own form.
    var isEditable: Bool {
        self.canChange ?? true
    }
}

/// POST /api/users/public-author — accept (or later edit) the public identity.
struct PublicAuthorIdentityPayload: Encodable {
    let handle: String
    let displayName: String
    let avatar: String?
    /// Empty string clears the bio; omitting the key entirely leaves it alone.
    let bio: String?
}

struct PublicAuthorIdentityResponse: Decodable {
    let ok: Bool?
    let confirmed: Bool?
    let handle: String?
    let displayName: String?
}
