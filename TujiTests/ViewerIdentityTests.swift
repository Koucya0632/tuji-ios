// Pins "who is looking, and is this theirs".
//
// Four questions the app used to answer fourteen times in four mechanisms:
// `user == nil` (今天, 我), `if case .signedIn` (設定, 圖鑑, 主題, 我的進度),
// `uid.caseInsensitiveCompare(handle)` (物見 ×2, 作者主頁), and three copies of
// nickname → username → email-local. None of them were reachable: every one was
// a `private var` on a `View`.
//
// The split was not academic. `MeView` used the first mechanism and hosted
// `MeProgressSections`, which used the second — and both feed
// `CompletionReadout.Inputs.isGuest`, the flag that decides whether 完成度 counts
// the local learned set or the server rows.
//
// The rules live on `AuthState` rather than on `AuthService` because the service
// has a private init and a stored Supabase client that traps without Info.plist
// keys. The state is a plain enum, so these assertions need nothing.

import Foundation
import Testing
@testable import Tuji

struct ViewerIdentityTests {
    private func user(
        username: String? = "TJ12345678",
        nickname: String? = nil,
        email: String? = nil,
        avatar: String? = nil
    )
        -> SessionUser
    {
        SessionUser(
            id: UUID(),
            email: email,
            username: username,
            nickname: nickname,
            avatar: avatar
        )
    }

    // MARK: - isGuest

    /// Everything that is not a signed-in session is a guest, including the two
    /// states the shell never renders these screens in. The two mechanisms
    /// agreed only because `RootView` maps `.guest` to `user: nil` by hand.
    @Test
    func onlyASignedInSessionIsNotAGuest() {
        #expect(AuthState.signedIn(self.user()).isGuest == false)
        #expect(AuthState.guest.isGuest)
        #expect(AuthState.signedOut.isGuest)
        #expect(AuthState.checking.isGuest)
    }

    // MARK: - uid

    @Test
    func uidIsTheUsernameWhenThereIsOne() {
        #expect(AuthState.signedIn(self.user(username: "TJ55854015")).uid == "TJ55854015")
    }

    /// An account the server has not minted a UID for is not identifiable, and
    /// neither is a guest. An empty string is the same as absent — it was the
    /// `!uid.isEmpty` half that four of the call sites remembered and one didn't.
    @Test
    func uidIsAbsentWithoutAMintedUsername() {
        #expect(AuthState.signedIn(self.user(username: nil)).uid == nil)
        #expect(AuthState.signedIn(self.user(username: "")).uid == nil)
        #expect(AuthState.guest.uid == nil)
    }

    // MARK: - owns(handle:)

    /// The handle *is* the immutable TJ-UID, so the compare is case-insensitive
    /// — the rule `BlockStore.isBlocked` already documented and four screens
    /// re-derived.
    @Test
    func ownershipIgnoresCase() {
        let state = AuthState.signedIn(self.user(username: "TJ12345678"))
        #expect(state.owns(handle: "TJ12345678"))
        #expect(state.owns(handle: "tj12345678"))
        #expect(!state.owns(handle: "TJ87654321"))
    }

    /// A viewer with no account owns nothing — this is what stops 檢舉/封鎖 being
    /// offered on your own profile, and what stops it being offered to a guest
    /// who has no account to act with.
    @Test
    func aViewerWithoutAUidOwnsNothing() {
        #expect(!AuthState.guest.owns(handle: "TJ12345678"))
        #expect(!AuthState.signedIn(self.user(username: nil)).owns(handle: "TJ12345678"))
    }

    /// An empty handle is not "everyone's" — an item whose author the payload
    /// omitted must not read as the viewer's own.
    @Test
    func anEmptyHandleIsOwnedByNobody() {
        #expect(!AuthState.signedIn(self.user(username: "TJ12345678")).owns(handle: ""))
    }

    // MARK: - displayName

    @Test
    func displayNamePrefersTheNicknameThenTheUidThenTheEmail() {
        let full = self.user(username: "TJ1", nickname: "阿貓", email: "cat@example.com")
        #expect(AuthState.signedIn(full).displayName(fallback: "x") == "阿貓")

        let noNickname = self.user(username: "TJ1", nickname: nil, email: "cat@example.com")
        #expect(AuthState.signedIn(noNickname).displayName(fallback: "x") == "TJ1")

        let emailOnly = self.user(username: nil, nickname: nil, email: "cat@example.com")
        #expect(AuthState.signedIn(emailOnly).displayName(fallback: "x") == "cat")
    }

    /// Empty is the same as absent at every step — a nickname cleared to "" must
    /// fall through rather than render a blank greeting.
    @Test
    func anEmptyNicknameFallsThrough() {
        let blank = self.user(username: "TJ1", nickname: "", email: nil)
        #expect(AuthState.signedIn(blank).displayName(fallback: "x") == "TJ1")
    }

    /// The fallback is the caller's, because it is that screen's copy: 今天
    /// greets 「探險者」 and 我 titles the row 「Tuji 探險者」. Two sentences, not a
    /// divergence — so the seam takes it rather than picking one.
    @Test
    func theFallbackBelongsToTheCaller() {
        #expect(AuthState.guest.displayName(fallback: "探險者") == "探險者")
        #expect(AuthState.guest.displayName(fallback: "Tuji 探險者") == "Tuji 探險者")

        let bare = self.user(username: nil, nickname: nil, email: nil)
        #expect(AuthState.signedIn(bare).displayName(fallback: "探險者") == "探險者")
    }

    // MARK: - authorRef

    /// The byline 物見 renders for the viewer's own work. Three screens used to
    /// assemble this by hand: two fields through the seam and the third
    /// (`avatar`) by pattern-matching `auth.state` again, because the seam did
    /// not answer it.
    @Test
    func authorRefIsTheViewersOwnByline() {
        let full = self.user(username: "TJ55854015", nickname: "阿貓", avatar: "cat.jpg")
        let ref = AuthState.signedIn(full).authorRef

        #expect(ref?.handle == "TJ55854015")
        #expect(ref?.displayName == "阿貓")
        #expect(ref?.avatar == "cat.jpg")
    }

    /// A guest has no byline at all — not a byline with an empty handle, which
    /// would render a link to nowhere.
    @Test
    func aGuestHasNoAuthorRef() {
        #expect(AuthState.guest.authorRef == nil)
        #expect(AuthState.signedOut.authorRef == nil)
        #expect(AuthState.checking.authorRef == nil)
    }

    /// `handle` is the link target for the author route, so an account whose UID
    /// mirror has not arrived yet has nothing to link to. Better no byline than
    /// one that 404s — and this is reachable: the mirror lags registration.
    @Test
    func anAccountWithoutAUidHasNoAuthorRef() {
        #expect(AuthState.signedIn(self.user(username: nil)).authorRef == nil)
        #expect(AuthState.signedIn(self.user(username: "")).authorRef == nil)
    }

    /// The display name falls back to the UID, never to the email — the same
    /// rule `displayName` states, applied here so the byline cannot leak an
    /// address the profile page would never show.
    @Test
    func authorRefFallsBackToTheUidNotTheEmail() {
        let noNickname = self.user(username: "TJ1", nickname: nil, email: "cat@example.com")
        #expect(AuthState.signedIn(noNickname).authorRef?.displayName == "TJ1")
    }

    /// An author who has chosen no photo gets the single default black cat, and
    /// that default lives here rather than in the one `View` that used to spell
    /// it — the next screen to render a byline gets it for free.
    @Test
    func aMissingPhotoIsTheDefaultAvatar() {
        #expect(AuthState.signedIn(self.user(avatar: nil)).authorRef?.avatar == AtlasAuthorRef.defaultAvatar)
    }

    // MARK: - ViewerRelationship

    /// A stub rather than `AuthState`: the relationship is a protocol extension
    /// derived from `isGuest` and `owns(handle:)`, so what is worth pinning is
    /// that derivation — any conformer gets the same three answers.
    private struct Viewer: ViewerIdentity {
        var isGuest = false
        var ownedHandle: String?

        var uid: String? {
            self.ownedHandle
        }

        func owns(handle: String) -> Bool {
            guard let ownedHandle, !handle.isEmpty else { return false }
            return ownedHandle.caseInsensitiveCompare(handle) == .orderedSame
        }

        func displayName(fallback: String) -> String {
            fallback
        }

        var authorRef: AtlasAuthorRef? {
            nil
        }
    }

    @Test
    @MainActor
    func theRelationshipIsMineTheirsOrGuest() {
        let me = Viewer(ownedHandle: "TJ12345678")
        #expect(me.relationship(toAuthor: "TJ12345678") == .mine)
        #expect(me.relationship(toAuthor: "tj12345678") == .mine, "the UID compare is case-insensitive")
        #expect(me.relationship(toAuthor: "TJ87654321") == .theirs)

        let guest = Viewer(isGuest: true, ownedHandle: nil)
        #expect(guest.relationship(toAuthor: "TJ12345678") == .guest)
    }

    /// A public item whose byline never resolved is nothing to anybody — which
    /// is what the empty-handle guards each screen carried already meant.
    @Test
    @MainActor
    func thereIsNoRelationshipWithoutAnAuthor() {
        let me = Viewer(ownedHandle: "TJ12345678")
        #expect(me.relationship(toAuthor: nil) == nil)
        #expect(me.relationship(toAuthor: "") == nil)
    }

    /// The bug this exists to make unrepresentable: a signed-in viewer is
    /// always exactly one of `.mine` or `.theirs`, so a screen that branches on
    /// the relationship cannot fall through both arms and draw nothing. The nav
    /// bar on 作者主頁 did, for anyone who arrived through a byline — every
    /// byline in the app pushes `isSelf: false`.
    @Test
    @MainActor
    func aSignedInViewerIsAlwaysOneOrTheOther() {
        let me = Viewer(ownedHandle: "TJ12345678")
        for handle in ["TJ12345678", "TJ87654321"] {
            let relationship = me.relationship(toAuthor: handle)
            #expect(relationship == .mine || relationship == .theirs)
            #expect(relationship != .guest)
        }
    }
}
