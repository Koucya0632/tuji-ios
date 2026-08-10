// View model for 編輯個人資料.
//
// This screen is the project convention's own worked example of what belongs in
// a view model — "form + async state" — and it was the one screen still doing
// all of it inside the `View`: eleven `@State` properties, the dirty-tracking
// that decides whether 儲存 is live, both validity rules, and both network
// calls. Its `profiles` dependency was a hardcoded `private let ... = .shared`
// with no init seam, so none of it could be tested even from inside the module.
// The one piece that *was* tested is `profileSeed`, because someone had already
// lifted it out as a `static func`; it moves here so the whole screen's logic
// has one home.
//
// The View keeps what is genuinely presentation: the cropped-avatar preview
// image, the picker flow, and applying the saved identity to the session (a VM
// does not reach `AuthService`, the same way it does not reach
// `AnalyticsService`) — `save()` hands the result back instead.

import Observation
import OSLog
import SwiftUI

@MainActor
@Observable
final class EditProfileVM {
    static let nicknameMax = 20
    static let bioMax = 80

    /// A profile as the server has it — the thing an edit is compared against.
    struct Loaded: Equatable {
        var nickname: String
        var bio: String
        var avatar: String
    }

    /// Keeps the edit draft and server truth separate. A legacy auth-session
    /// nickname may still be useful as a draft, but it is not public until the
    /// profiles row contains it.
    struct ProfileSeed: Equatable {
        var draft: Loaded
        var saved: Loaded
    }

    /// What a successful save produced, handed back for the View to mirror into
    /// the session and dismiss on.
    struct SavedIdentity: Equatable {
        /// nil when the display name fell back to the UID — i.e. no nickname.
        let nickname: String?
        let avatar: String
    }

    var nickname = ""
    var bio = ""
    private(set) var avatar = MascotPose.face.rawValue
    private(set) var pendingAvatarData: Data?
    private(set) var saving = false
    private(set) var loading = true
    private(set) var error: Error?
    /// What the server had when the screen opened, so `dirty` compares against
    /// the truth rather than against a stale session copy.
    private(set) var loaded: Loaded?
    /// Server truth for the UID. The session mirror can lag it, and this screen
    /// is where someone goes to check what their UID actually is.
    private(set) var serverUid: String?

    private let profiles: ProfileEditing
    private let log = Logger(subsystem: "app.tuji.ios", category: "edit-profile")

    init(profiles: ProfileEditing = LiveProfileModule.shared) {
        self.profiles = profiles
    }

    // MARK: - Derived

    var trimmedNickname: String {
        self.nickname.trimmingCharacters(in: .whitespaces)
    }

    var trimmedBio: String {
        self.bio.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var nicknameIsValid: Bool {
        self.trimmedNickname.count <= Self.nicknameMax
    }

    var bioIsValid: Bool {
        self.trimmedBio.count <= Self.bioMax
    }

    var dirty: Bool {
        guard let loaded else { return false }
        if self.pendingAvatarData != nil { return true }
        return Loaded(
            nickname: self.trimmedNickname,
            bio: self.trimmedBio,
            avatar: self.avatar
        ) != loaded
    }

    var canSave: Bool {
        self.dirty && !self.saving && !self.loading && self.nicknameIsValid && self.bioIsValid
    }

    var hasCustomAvatar: Bool {
        if self.pendingAvatarData != nil { return true }
        return URL(string: self.avatar)?.scheme == "https"
    }

    // MARK: - Avatar

    /// A freshly cropped photo, not yet uploaded. Held here (rather than only as
    /// a preview image on the View) because it is what makes the form dirty and
    /// what `save()` uploads.
    func stageAvatar(data: Data) {
        self.pendingAvatarData = data
    }

    /// Choosing the built-in mascot clears any staged upload — otherwise the
    /// pending photo would win at save time and silently undo the choice.
    func useDefaultAvatar() {
        self.pendingAvatarData = nil
        self.avatar = MascotPose.face.rawValue
    }

    // MARK: - Seeding

    static func profileSeed(session: SessionUser?, server: UserMeUser?) -> ProfileSeed {
        var seeded = Loaded(nickname: "", bio: "", avatar: MascotPose.face.rawValue)
        if let session {
            seeded.nickname = session.nickname ?? ""
            if let avatar = session.avatar, URL(string: avatar)?.scheme == "https" {
                seeded.avatar = avatar
            }
        }
        var saved = seeded
        if let server {
            seeded.nickname = server.nickname ?? seeded.nickname
            seeded.bio = server.bio ?? ""
            if let avatar = server.avatar, URL(string: avatar)?.scheme == "https" {
                seeded.avatar = avatar
            }
            saved = seeded
            // A successful /users/me response is authoritative. Keep a stale
            // session nickname in the field as a convenient draft, but compare
            // it against the empty public value so Save becomes available and
            // publishing still requires an explicit tap.
            saved.nickname = server.nickname ?? ""
        }
        return ProfileSeed(draft: seeded, saved: saved)
    }

    // MARK: - Actions

    /// The 簽名 has no other read path, so the screen loads its own copy rather
    /// than seeding from the cached session (which carries no bio at all).
    func load(session: SessionUser?) async {
        guard self.loading else { return }
        defer { self.loading = false }
        var seed = Self.profileSeed(session: session, server: nil)
        if let me = try? await self.profiles.load() {
            self.serverUid = me.username
            seed = Self.profileSeed(session: session, server: me)
        }
        self.nickname = seed.draft.nickname
        self.bio = seed.draft.bio
        self.avatar = seed.draft.avatar
        self.loaded = seed.saved
    }

    /// Returns the saved identity on success, nil on failure (`error` is set).
    func save() async -> SavedIdentity? {
        self.saving = true
        self.error = nil
        defer { self.saving = false }
        let newNickname = self.trimmedNickname.isEmpty ? nil : self.trimmedNickname
        do {
            // Only send an avatar *string* when the user picked the built-in
            // mascot; a staged photo travels as data and would otherwise be
            // contradicted by a stale URL.
            let avatarChange = self.pendingAvatarData == nil && self.avatar != self.loaded?.avatar
                ? self.avatar
                : nil
            let change = ProfileEditChange(
                nickname: newNickname,
                avatar: avatarChange,
                bio: self.trimmedBio
            )
            let author = try await self.profiles.edit(change, avatarData: self.pendingAvatarData)
            self.log.info("profile saved")
            return SavedIdentity(
                nickname: author.displayName == author.handle ? nil : author.displayName,
                avatar: author.avatar
            )
        } catch {
            self.error = error
            self.log.error("profile save failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }
}
