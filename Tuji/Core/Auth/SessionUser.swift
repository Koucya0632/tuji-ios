// Display-side view of the currently-authenticated user.
// Mirrors fields from Supabase's User but stays UI-friendly (username +
// avatar pulled from raw_user_meta_data populated by the handle_new_user
// trigger on the backend).

import Foundation
import Supabase

struct SessionUser: Equatable, Hashable {
    let id: UUID
    let email: String?
    let username: String?
    let avatar: String?

    init(from user: Supabase.User) {
        id = user.id
        email = user.email
        let meta = user.userMetadata
        username = meta["username"]?.stringValue
        avatar = meta["avatar"]?.stringValue
    }
}
