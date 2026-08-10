// Pins `SessionUser.merging` — how server truth is applied over the session's
// user_metadata mirror.
//
// Why this exists: the UID lives in `profiles.username`, and the session only
// carries a copy minted when the token was issued. Two writers used to keep
// that copy fresh (the email signup payload and the public-author route); both
// were removed when the handle became a machine-minted UID, so the mirror went
// stale for email accounts and was simply absent for OAuth ones. The visible
// symptom was a permanently disabled 我的公開主頁 row, and the invisible one was
// an author link pointing at a pre-migration handle that now 404s.
//
// `merging` is the reconciliation, so the rule it must never break is: a
// partial or empty server payload must not blank a value the client already
// holds.

import Foundation
import Testing
@testable import Tuji

@MainActor
struct SessionUserMirrorTests {
    private func user(
        username: String? = "TJ00000042",
        nickname: String? = "Mika",
        avatar: String? = "face"
    )
        -> SessionUser
    {
        SessionUser(
            id: UUID(),
            email: "mika@example.com",
            username: username,
            nickname: nickname,
            avatar: avatar
        )
    }

    /// The case that shipped broken: OAuth accounts never had the key at all.
    @Test
    func serverFillsAUidTheSessionNeverHad() {
        let merged = self.user(username: nil)
            .merging(username: "TJ73168628", nickname: nil, avatar: nil)
        #expect(merged.username == "TJ73168628")
    }

    /// The other half: email accounts held a PRE-migration handle, which now
    /// resolves to a 404 author page. Server truth has to win, not merely fill.
    @Test
    func serverOverwritesAStaleUid() {
        let merged = self.user(username: "rex0632")
            .merging(username: "TJ73168628", nickname: nil, avatar: nil)
        #expect(merged.username == "TJ73168628")
    }

    /// A dropped or partial response must never blank what the client has —
    /// otherwise a flaky fetch would disable the row it was meant to fix.
    @Test
    func anEmptyPayloadLeavesEverythingAlone() {
        let original = self.user()
        let merged = original.merging(username: nil, nickname: nil, avatar: nil)
        #expect(merged == original)
    }

    @Test
    func eachFieldFallsBackIndependently() {
        let merged = self.user()
            .merging(username: "TJ00000001", nickname: nil, avatar: nil)
        #expect(merged.username == "TJ00000001")
        #expect(merged.nickname == "Mika")
        #expect(merged.avatar == "face")
    }

    /// Reproduces the shipped mismatch: the migration cleared the public
    /// profile nickname but left the old auth-session mirror behind. The old
    /// value is useful as an edit draft, but must remain dirty until the user
    /// explicitly saves it back to the public profile.
    @Test
    func staleSessionNicknameIsAnUnsavedDraft() {
        let server = UserMeUser(
            id: UUID().uuidString,
            email: "mika@example.com",
            username: "TJ00000042",
            nickname: nil,
            avatar: "face",
            bio: nil
        )

        let seed = EditProfileVM.profileSeed(session: self.user(nickname: "Mika"), server: server)

        #expect(seed.draft.nickname == "Mika")
        #expect(seed.saved.nickname == "")
        #expect(seed.draft != seed.saved)
    }

    @Test
    func publicNicknameOverridesTheSessionDraftAndStartsClean() {
        let server = UserMeUser(
            id: UUID().uuidString,
            email: "mika@example.com",
            username: "TJ00000042",
            nickname: "Public Mika",
            avatar: "face",
            bio: nil
        )

        let seed = EditProfileVM.profileSeed(session: self.user(nickname: "Old Mika"), server: server)

        #expect(seed.draft.nickname == "Public Mika")
        #expect(seed.saved.nickname == "Public Mika")
        #expect(seed.draft == seed.saved)
    }

    @Test
    func unavailableServerDoesNotInventAnUnsavedChange() {
        let seed = EditProfileVM.profileSeed(session: self.user(nickname: "Mika"), server: nil)

        #expect(seed.draft.nickname == "Mika")
        #expect(seed.draft == seed.saved)
    }

    /// Identity is keyed on the account, not on the mirror — merging must not
    /// invent a different user.
    @Test
    func mergingPreservesIdentity() {
        let original = self.user()
        let merged = original.merging(username: "TJ99999999", nickname: "Redtea", avatar: "wave")
        #expect(merged.id == original.id)
        #expect(merged.email == original.email)
    }
}
