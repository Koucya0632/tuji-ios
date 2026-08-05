// 編輯個人資料 — the one screen that owns the whole profile.
//
// It used to be two: this one edited a *private* in-app greeting, and a
// separate 公開作者身分 sheet published an identity and asked consent for it.
// That split existed because `username` defaulted to the email local part and
// `nickname` was silently seeded from the Apple Sign-In full name, so the app
// held personal data in fields the community layer wanted to show.
//
// Neither is true any more. The UID is machine-minted and immutable, and no
// name is ever written that the user did not type here. So there is one screen,
// everything on it is public, and there is nothing left to consent to.

import OSLog
import SwiftUI
import UIKit

struct EditProfileView: View {
    @Environment(AuthService.self) private var auth
    @Environment(\.dismiss) private var dismiss
    private let profiles: ProfileEditing = LiveProfileModule.shared

    @State private var nickname: String = ""
    @State private var bio: String = ""
    @State private var avatar: String = MascotPose.face.rawValue
    @State private var pendingAvatarData: Data?
    @State private var pendingAvatarImage: UIImage?
    @State private var avatarPicker = AvatarPicker(encoding: .profile, cropFrame: .circle)
    @State private var saving = false
    @State private var loading = true
    @State private var error: Error?
    /// What the server had when the screen opened, so `dirty` compares against
    /// the truth rather than against a stale session copy.
    @State private var loaded: Loaded?
    /// Server truth for the UID. The session mirror can lag it, and this screen
    /// is where someone goes to check what their UID actually is.
    @State private var serverUid: String?

    private let log = Logger(subsystem: "app.tuji.ios", category: "edit-profile")

    struct Loaded: Equatable {
        var nickname: String
        var bio: String
        var avatar: String
    }

    struct ProfileSeed: Equatable {
        var draft: Loaded
        var saved: Loaded
    }

    static let nicknameMax = 20
    static let bioMax = 80

    var body: some View {
        VStack(spacing: 0) {
            TujiNavBar(leading: .back) {
                TujiNavTextAction(
                    title: self.saving ? "儲存中…" : "儲存",
                    isEnabled: self.canSave
                ) {
                    Task { await self.save() }
                }
            }
            self.form
        }
        .background(.tujiPaper)
        .navigationTitle("編輯個人資料")
        .toolbar(.hidden, for: .navigationBar)
        .task {
            self.connectAvatarPicker()
            await self.load()
        }
        .avatarPicker(self.avatarPicker, title: "更換頭像") {
            if self.hasCustomAvatar {
                Button("使用預設黑貓頭像") {
                    self.avatar = MascotPose.face.rawValue
                    self.pendingAvatarData = nil
                    self.pendingAvatarImage = nil
                }
            }
        }
    }

    private var form: some View {
        ScrollView {
            VStack(spacing: Space.s4) {
                self.heroAvatar
                self.nicknameField
                self.bioField
                self.uidField
                if let message = self.error?.localizedDescription ?? self.avatarPicker.errorMessage {
                    Text(message)
                        .font(.tujiLabel)
                        .foregroundStyle(.tujiAlert)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(.horizontal, Space.s4)
            .padding(.bottom, Space.s5)
        }
    }

    /// 個人資料 doesn't upload on pick — the encoded photo is stashed and sent
    /// with 儲存 — so delivery is a local decode that only fails on an
    /// unreadable image.
    private func connectAvatarPicker() {
        self.avatarPicker.onDeliver { data in
            guard let image = UIImage(data: data) else { return false }
            self.error = nil
            self.pendingAvatarData = data
            self.pendingAvatarImage = image
            return true
        }
    }

    private var heroAvatar: some View {
        Button {
            self.avatarPicker.begin()
        } label: {
            VStack(spacing: Space.s2) {
                ZStack(alignment: .bottomTrailing) {
                    Group {
                        if let pendingAvatarImage {
                            Image(uiImage: pendingAvatarImage)
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(width: 104, height: 104)
                                .clipShape(.circle)
                                .overlay(Circle().stroke(.tujiTeal, lineWidth: 2))
                                .shadow(color: .black.opacity(0.08), radius: 10, x: 0, y: 4)
                        } else {
                            ProfileAvatar(avatar: self.avatar, size: 104, selected: true)
                        }
                    }

                    Image(systemName: "camera.fill")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 34, height: 34)
                        .background(.tujiTeal, in: .circle)
                        .overlay(Circle().stroke(.tujiPaper, lineWidth: 3))
                }
                Text("點一下更換頭像")
                    .font(.tujiLabel)
                    .foregroundStyle(.tujiInk3)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
        .disabled(self.saving || self.loading)
        .accessibilityLabel("更換頭像")
    }

    private var nicknameField: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Text("暱稱")
                .font(.tujiLabel)
                .tracking(2)
                .foregroundStyle(.tujiInk3)
            TextField("大家會怎麼稱呼你", text: self.$nickname)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .font(.tujiBodySm)
                .padding(.horizontal, Space.s3)
                .padding(.vertical, Space.s3)
                .background(.tujiPaper, in: .rect(cornerRadius: Radius.r0))
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.r0)
                        .stroke(
                            self.nicknameIsValid ? .tujiRule : Color.tujiAlert,
                            lineWidth: 1
                        )
                )
            // Not required: an empty 暱稱 falls back to the UID, which is a
            // valid public identity rather than an error state.
            Text("最長 20 字，留空就顯示你的 UID")
                .font(.tujiLabel)
                .foregroundStyle(.tujiInk3)
        }
    }

    private var bioField: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Text("簽名")
                .font(.tujiLabel)
                .tracking(2)
                .foregroundStyle(.tujiInk3)
            TextField("介紹一下你自己", text: self.$bio, axis: .vertical)
                .lineLimit(2...4)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .font(.tujiBodySm)
                .padding(.horizontal, Space.s3)
                .padding(.vertical, Space.s3)
                .background(.tujiPaper, in: .rect(cornerRadius: Radius.r0))
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.r0)
                        .stroke(
                            self.bioIsValid ? .tujiRule : Color.tujiAlert,
                            lineWidth: 1
                        )
                )
            HStack {
                Text("不能放網址或個人資訊")
                    .font(.tujiLabel)
                    .foregroundStyle(.tujiInk3)
                Spacer()
                Text(verbatim: "\(Self.bioMax - self.trimmedBio.count)")
                    .font(.tujiLabel)
                    .foregroundStyle(self.bioIsValid ? .tujiInk3 : .tujiAlert)
                    .monospacedDigit()
            }
        }
    }

    /// Read-only by design: the UID is the one thing on this screen the user
    /// cannot change, and it is what every author link points at.
    private var uidField: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Text("UID")
                .font(.tujiLabel)
                .tracking(2)
                .foregroundStyle(.tujiInk3)
            Text(self.uid)
                .font(.tujiMono)
                .foregroundStyle(.tujiInk3)
                .padding(.horizontal, Space.s3)
                .padding(.vertical, Space.s3)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.tujiPaper2.opacity(0.06), in: .rect(cornerRadius: Radius.r0))
            Text("系統自動配發，不能修改")
                .font(.tujiLabel)
                .foregroundStyle(.tujiInk3)
        }
    }

    // MARK: - State

    private var uid: String {
        if let serverUid, !serverUid.isEmpty { return serverUid }
        if case let .signedIn(user) = auth.state, let uid = user.username, !uid.isEmpty {
            return uid
        }
        return "—"
    }

    private var trimmedNickname: String {
        self.nickname.trimmingCharacters(in: .whitespaces)
    }

    private var trimmedBio: String {
        self.bio.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var nicknameIsValid: Bool {
        self.trimmedNickname.count <= Self.nicknameMax
    }

    private var bioIsValid: Bool {
        self.trimmedBio.count <= Self.bioMax
    }

    private var dirty: Bool {
        guard let loaded else { return false }
        if self.pendingAvatarData != nil { return true }
        return Loaded(nickname: self.trimmedNickname, bio: self.trimmedBio, avatar: self.avatar) != loaded
    }

    private var canSave: Bool {
        self.dirty && !self.saving && !self.loading && self.nicknameIsValid && self.bioIsValid
    }

    private var hasCustomAvatar: Bool {
        if self.pendingAvatarData != nil { return true }
        return URL(string: self.avatar)?.scheme == "https"
    }

    /// Keeps the edit draft and server truth separate. A legacy auth-session
    /// nickname may still be useful as a draft, but it is not public until the
    /// profiles row contains it.
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

    /// The 簽名 has no other read path, so the screen loads its own copy rather
    /// than seeding from the cached session (which carries no bio at all).
    private func load() async {
        guard self.loading else { return }
        defer { self.loading = false }
        let session: SessionUser? = if case let .signedIn(user) = auth.state { user } else { nil }
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

    private func save() async {
        self.saving = true
        self.error = nil
        defer { self.saving = false }
        let newNickname = self.trimmedNickname.isEmpty ? nil : self.trimmedNickname
        do {
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
            let savedNickname = author.displayName == author.handle ? nil : author.displayName
            self.auth.applyProfile(nickname: savedNickname, avatar: author.avatar)
            self.dismiss()
        } catch {
            self.error = error
            self.log.error("profile save failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}
