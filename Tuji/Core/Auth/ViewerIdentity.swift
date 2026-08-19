// Who is looking, and is this theirs.
//
// Four questions the app asks constantly and used to answer fourteen times, in
// four mechanisms that did not agree:
//
//   • `user == nil`                          — 今天, 我
//   • `if case .signedIn = auth.state`       — 設定, 圖鑑, 主題, 我的進度
//   • `uid.caseInsensitiveCompare(handle)`   — 物見 ×2, 作者主頁, CollectionDetailVM
//   • nickname ?? username ?? email-local    — 今天, 我, 物見（後者還多一個 ?? "face"）
//
// The split was not academic. `MeView` answered with the first mechanism and
// hosted `MeProgressSections`, which answered with the second — and both feed
// `CompletionReadout.Inputs.isGuest`, the flag that decides whether 完成度 counts
// the local learned set or the server rows. They agreed only because `RootView`
// happens to map `.guest` to `user: nil` by hand.
//
// The consuming half of this seam already existed: `CompletionReadout.Inputs`
// and `TodayDecisions.Inputs` both take `isGuest` as an input, are tested, and
// are load-bearing. What was missing was a producer. There were fourteen.

import Foundation

/// The viewer, as the screens need to know them.
///
/// A read seam in the shape `LanguageContext` already uses: narrow, injected,
/// conformed by the store that holds the real thing. Read live at call time —
/// signing in mid-session must take effect on the next render.
@MainActor
protocol ViewerIdentity {
    /// Browsing without an account.
    ///
    /// Guests keep progress locally, so this is not cosmetic: it changes what
    /// 完成度 counts and what 今天 offers.
    var isGuest: Bool { get }

    /// The public UID (`TJ` + 8 digits), or nil when there is no account.
    ///
    /// System-assigned and immutable, which is why comparing it is safe.
    var uid: String? { get }

    /// Is this handle the viewer's own?
    ///
    /// Case-insensitive, for the reason `BlockStore.isBlocked` already states:
    /// the handle *is* the immutable TJ-UID, so the compare is safe and spares
    /// every caller from worrying about how it was spelled. A viewer with no
    /// account owns nothing.
    func owns(handle: String) -> Bool

    /// Editable display name → UID → the local part of the email address.
    ///
    /// `fallback` stays the caller's because it is that screen's copy: 今天
    /// greets 「探險者」 and 我 titles the row 「Tuji 探險者」, and those are
    /// different sentences rather than a divergence to collapse.
    func displayName(fallback: String) -> String
}

/// The rules themselves, on the state rather than the service.
///
/// `AuthService.init` is private and its stored Supabase client `fatalError`s
/// without Info.plist keys, so nothing could stand one up in a test. `AuthState`
/// is a plain enum — the same reason `AuthSession` was split out of the service
/// in the first place. The service below is a one-line adapter over these.
extension AuthState {
    var isGuest: Bool {
        if case .signedIn = self { return false }
        return true
    }

    var uid: String? {
        guard case let .signedIn(user) = self else { return nil }
        guard let username = user.username, !username.isEmpty else { return nil }
        return username
    }

    func owns(handle: String) -> Bool {
        guard let uid, !handle.isEmpty else { return false }
        return uid.caseInsensitiveCompare(handle) == .orderedSame
    }

    func displayName(fallback: String) -> String {
        guard case let .signedIn(user) = self else { return fallback }
        if let nickname = user.nickname, !nickname.isEmpty { return nickname }
        if let username = user.username, !username.isEmpty { return username }
        if let email = user.email, let local = email.split(separator: "@").first {
            return String(local)
        }
        return fallback
    }
}

extension AuthService: ViewerIdentity {
    var isGuest: Bool {
        self.state.isGuest
    }

    var uid: String? {
        self.state.uid
    }

    func owns(handle: String) -> Bool {
        self.state.owns(handle: handle)
    }

    func displayName(fallback: String) -> String {
        self.state.displayName(fallback: fallback)
    }
}
