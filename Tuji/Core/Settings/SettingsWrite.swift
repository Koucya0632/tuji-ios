// What to do with a settings change, given whose settings are on screen.
//
// POST /api/users/settings takes the whole object, so every save sends every
// field — the one the user touched and all the ones they did not. Before the
// account's settings have arrived, "all the ones they did not" are this
// device's defaults: no themes chosen, the default daily goal, the default
// accent. A change made in that window wrote them over the account. The launch
// read only has to fail once — a timeout while online is enough — and the next
// tap in 設定 empties 學習主題 on every device the account is signed in on.
//
// Applying the change locally and saving it later does not fix that: the screen
// the change was made on showed the defaults too. The 學習主題 grid computes the
// whole new selection from the one on screen, so "add 廚房" made against an
// empty grid *is* "replace twelve themes with 廚房", however late it is sent.
// The change itself is wrong, not just its timing.
//
// A guest has no server row to overwrite and nothing to save with; their
// settings live on this device, as they always have. Android holds the same
// rule in `core:study`'s `SettingsWrite`.

enum SettingsWrite: Equatable {
    /// The account's settings are on screen: apply, then save.
    case applyAndSave
    /// A guest: apply on this device. There is nothing to save to.
    case applyLocally
    /// Signed in, and the account's settings have not arrived. Drop it.
    case refuse

    static func decide(signedIn: Bool, loaded: Bool) -> SettingsWrite {
        guard signedIn else { return .applyLocally }
        return loaded ? .applyAndSave : .refuse
    }
}
