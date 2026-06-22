// Display-side view of the currently-authenticated user.
// Mirrors fields from Supabase's User but stays UI-friendly (username +
// avatar pulled from raw_user_meta_data populated by the handle_new_user
// trigger on the backend).

import Foundation
import Supabase

struct SessionUser: Equatable, Hashable {
    let id: UUID
    let email: String?
    /// System-assigned handle (immutable). Shown as @handle.
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
}
