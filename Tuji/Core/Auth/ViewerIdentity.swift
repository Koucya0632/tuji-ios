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

/// What the viewer is to a piece of someone's work.
///
/// Every moderation affordance in 物見 is a function of these three, and each
/// screen was recombining `isGuest` and `owns(handle:)` into its own predicate:
/// 物見詳情 spelled it `!isGuest && !owns` for 檢舉/封鎖 and `owns` alone for the
/// 「你的分享」 pill three hundred lines later, and 作者主頁 kept a pair
/// (`isOwnProfile` / `canModerate`) whose *third* consumer — the nav bar —
/// then went around both and asked a fourth question.
///
/// That was not academic: the nav bar branched on the route's `isSelf` alone,
/// so reaching your own profile through a byline (every byline pushes
/// `isSelf: false`) matched neither arm and drew **no control at all** — no
/// edit, no 更多. This is the shape `NavRoute` dropped `isSelf`'s default to
/// prevent, returning as a hard-coded argument.
enum ViewerRelationship: Hashable {
    /// No account. Both moderation endpoints require auth, so offering an
    /// action that can only 401 is worse than not offering it.
    case guest
    /// The viewer's own work. Nothing to report yourself for, and 封鎖 would
    /// hide your own 圖鑑 from you.
    case mine
    /// Someone else's, and the viewer is signed in.
    case theirs
}

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

    /// The viewer as an **Author identity** — the byline shape 物見 renders,
    /// for the viewer's own work. Nil for a guest, and for an account whose
    /// UID mirror has not arrived yet (there is nothing to link to).
    ///
    /// Here rather than at the call site because the seam answered three of
    /// this question's four parts and the fourth (`avatar`) it did not, so
    /// three screens pattern-matched `auth.state` again to reach past it for
    /// the one field — which is how the 「沒有頭像就用黑貓」 default came to be
    /// written in a `View` body. A seam is worth what it answers for the *next*
    /// consumer, not the last one.
    var authorRef: AtlasAuthorRef? { get }
}

extension ViewerIdentity {
    /// What the viewer is to work by `handle`.
    ///
    /// Nil when there is no author to be anything to — a public item whose
    /// byline never resolved. Callers read that as "no moderation
    /// affordances", which is what the empty-handle guards they each carried
    /// already meant.
    func relationship(toAuthor handle: String?) -> ViewerRelationship? {
        guard let handle, !handle.isEmpty else { return nil }
        if self.isGuest { return .guest }
        return self.owns(handle: handle) ? .mine : .theirs
    }
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

    /// Keyed on `uid`, not on the session's UUID: `handle` is the link target
    /// for the author route, so an account without a mirrored UID has no byline
    /// to render rather than a broken one. The display name falls back to the
    /// UID (never the email — see `displayName`), and a missing photo is the
    /// single default black cat.
    var authorRef: AtlasAuthorRef? {
        guard case let .signedIn(user) = self, let uid else { return nil }
        return AtlasAuthorRef(
            handle: uid,
            displayName: self.displayName(fallback: uid),
            avatar: user.avatar ?? AtlasAuthorRef.defaultAvatar
        )
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

    var authorRef: AtlasAuthorRef? {
        self.state.authorRef
    }
}
