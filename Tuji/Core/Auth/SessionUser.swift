// Display-side view of the currently-authenticated user.
//
// Fields are read from `raw_user_meta_data`, which is a MIRROR of `profiles`
// maintained by the backend — not the authority. The session carries whatever
// the token was minted with, so the mirror can lag a server-side change until
// the token refreshes. `AuthService.hydrateProfile()` reconciles it against
// /api/users/me, which reads `profiles` directly.

import Foundation
import Supabase

struct SessionUser: Equatable, Hashable {
    let id: UUID
    let email: String?
    /// The public UID (`TJ` + 8 digits). System-assigned and immutable — the
    /// user cannot change it, so a stale value here is always the mirror
    /// lagging, never a legitimate edit.
    let username: String?
    /// Editable display name. Falls back to `username` when nil.
    let nickname: String?
    let avatar: String?

    init(from user: Supabase.User) {
        id = user.id
        email = user.email
        let meta = user.userMetadata
        username = meta["username"]?.stringValue
        nickname = meta["nickname"]?.stringValue
        avatar = meta["avatar"]?.stringValue
    }

    init(id: UUID, email: String?, username: String?, nickname: String?, avatar: String?) {
        self.id = id
        self.email = email
        self.username = username
        self.nickname = nickname
        self.avatar = avatar
    }

    /// Returns a copy with an updated nickname — used to optimistically
    /// reflect a profile edit before the auth token refreshes its metadata.
    func withNickname(_ nickname: String?) -> SessionUser {
        SessionUser(id: id, email: email, username: username, nickname: nickname, avatar: avatar)
    }

    func withProfile(nickname: String?, avatar: String?) -> SessionUser {
        SessionUser(id: id, email: email, username: username, nickname: nickname, avatar: avatar)
    }

    /// Applies server truth over the session mirror. Each field falls back to
    /// what is already held, so a partial payload never blanks a good value.
    func merging(username: String?, nickname: String?, avatar: String?) -> SessionUser {
        SessionUser(
            id: self.id,
            email: self.email,
            username: username ?? self.username,
            nickname: nickname ?? self.nickname,
            avatar: avatar ?? self.avatar
        )
    }
}
