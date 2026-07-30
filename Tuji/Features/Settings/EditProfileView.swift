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

struct EditProfileView: View {
    @Environment(AuthService.self) private var auth
    @Environment(\.dismiss) private var dismiss
    private let users: UserRepository = LiveUserRepository.shared

    @State private var nickname: String = ""
    @State private var bio: String = ""
    @State private var pose: MascotPose = .face
    @State private var saving = false
    @State private var loading = true
    @State private var error: Error?
    /// What the server had when the screen opened, so `dirty` compares against
    /// the truth rather than against a stale session copy.
    @State private var loaded: Loaded?

    private let log = Logger(subsystem: "app.tuji.ios", category: "edit-profile")

    private struct Loaded: Equatable {
        var nickname: String
        var bio: String
        var pose: MascotPose
    }

    static let nicknameMax = 20
    static let bioMax = 80

    var body: some View {
        ScrollView {
            VStack(spacing: Space.s6) {
                self.heroAvatar
                self.avatarPicker
                self.nicknameField
                self.bioField
                self.uidField
                if let error {
                    Text(error.localizedDescription)
                        .font(.tujiCaption)
                        .foregroundStyle(.tujiCoral)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(.horizontal, Space.s6)
            .padding(.top, Space.s5)
            .padding(.bottom, Space.s12)
        }
        .background(.tujiBg)
        .navigationTitle("編輯個人資料")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task { await self.save() }
                } label: {
                    Text(self.saving ? LocalizedStringKey("儲存中…") : LocalizedStringKey("儲存"))
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(self.canSave ? .tujiTeal : .tujiInk4)
                }
                .disabled(!self.canSave)
            }
        }
        .task { await self.load() }
    }

    private var heroAvatar: some View {
        MascotAvatar(pose: self.pose, size: 104, selected: true)
            .frame(maxWidth: .infinity)
    }

    private var avatarPicker: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            Text("選擇黑貓頭像")
                .font(.tujiOverline)
                .tracking(2)
                .foregroundStyle(.tujiInk3)

            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: Space.s2), count: 3),
                spacing: Space.s2
            ) {
                ForEach(MascotPose.allCases, id: \.self) { candidate in
                    Button {
                        self.pose = candidate
                    } label: {
                        MascotAvatar(
                            pose: candidate,
                            size: 68,
                            selected: self.pose == candidate
                        )
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, Space.s2)
                        .background(.tujiCard, in: .rect(cornerRadius: Radius.md))
                        .overlay(
                            RoundedRectangle(cornerRadius: Radius.md)
                                .stroke(.tujiInk4.opacity(0.2), lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("頭像 \(candidate.rawValue)")
                    .accessibilityAddTraits(self.pose == candidate ? .isSelected : [])
                }
            }
        }
    }

    private var nicknameField: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Text("暱稱")
                .font(.tujiOverline)
                .tracking(2)
                .foregroundStyle(.tujiInk3)
            TextField("大家會怎麼稱呼你", text: self.$nickname)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .font(.tujiBody)
                .padding(.horizontal, Space.s4)
                .padding(.vertical, Space.s3)
                .background(.tujiCard, in: .rect(cornerRadius: Radius.md))
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.md)
                        .stroke(
                            self.nicknameIsValid ? .tujiInk4.opacity(0.25) : Color.tujiCoral,
                            lineWidth: 1
                        )
                )
            // Not required: an empty 暱稱 falls back to the UID, which is a
            // valid public identity rather than an error state.
            Text("最長 20 字，留空就顯示你的 UID")
                .font(.tujiCaption)
                .foregroundStyle(.tujiInk4)
        }
    }

    private var bioField: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Text("簽名")
                .font(.tujiOverline)
                .tracking(2)
                .foregroundStyle(.tujiInk3)
            TextField("介紹一下你自己", text: self.$bio, axis: .vertical)
                .lineLimit(2...4)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .font(.tujiBody)
                .padding(.horizontal, Space.s4)
                .padding(.vertical, Space.s3)
                .background(.tujiCard, in: .rect(cornerRadius: Radius.md))
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.md)
                        .stroke(
                            self.bioIsValid ? .tujiInk4.opacity(0.25) : Color.tujiCoral,
                            lineWidth: 1
                        )
                )
            HStack {
                Text("不能放網址或個人資訊")
                    .font(.tujiCaption)
                    .foregroundStyle(.tujiInk4)
                Spacer()
                Text(verbatim: "\(Self.bioMax - self.trimmedBio.count)")
                    .font(.tujiCaption)
                    .foregroundStyle(self.bioIsValid ? .tujiInk4 : .tujiCoral)
                    .monospacedDigit()
            }
        }
    }

    /// Read-only by design: the UID is the one thing on this screen the user
    /// cannot change, and it is what every author link points at.
    private var uidField: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Text("UID")
                .font(.tujiOverline)
                .tracking(2)
                .foregroundStyle(.tujiInk3)
            Text(self.uid)
                .font(.tujiMono)
                .foregroundStyle(.tujiInk3)
                .padding(.horizontal, Space.s4)
                .padding(.vertical, Space.s3)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.tujiInk4.opacity(0.06), in: .rect(cornerRadius: Radius.md))
            Text("系統自動配發，不能修改")
                .font(.tujiCaption)
                .foregroundStyle(.tujiInk4)
        }
    }

    // MARK: - State

    private var uid: String {
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
        return Loaded(nickname: self.trimmedNickname, bio: self.trimmedBio, pose: self.pose) != loaded
    }

    private var canSave: Bool {
        self.dirty && !self.saving && !self.loading && self.nicknameIsValid && self.bioIsValid
    }

    /// The 簽名 has no other read path, so the screen loads its own copy rather
    /// than seeding from the cached session (which carries no bio at all).
    private func load() async {
        guard self.loading else { return }
        defer { self.loading = false }
        var seeded = Loaded(nickname: "", bio: "", pose: .face)
        if case let .signedIn(user) = auth.state {
            seeded.nickname = user.nickname ?? ""
            seeded.pose = MascotPose(rawValue: user.avatar ?? "") ?? .face
        }
        if let me = try? await self.users.loadMe().user {
            seeded.nickname = me.nickname ?? seeded.nickname
            seeded.bio = me.bio ?? ""
            seeded.pose = MascotPose(rawValue: me.avatar ?? "") ?? seeded.pose
        }
        self.nickname = seeded.nickname
        self.bio = seeded.bio
        self.pose = seeded.pose
        self.loaded = seeded
    }

    private func save() async {
        self.saving = true
        self.error = nil
        defer { self.saving = false }
        let newNickname = self.trimmedNickname.isEmpty ? nil : self.trimmedNickname
        let payload = ProfileUpdatePayload(
            nickname: newNickname,
            avatar: self.pose.rawValue,
            bio: self.trimmedBio
        )
        do {
            _ = try await self.users.updateProfile(payload)
            self.log.info("profile saved")
            self.auth.applyProfile(nickname: newNickname, avatar: self.pose.rawValue)
            self.dismiss()
        } catch {
            self.error = error
            self.log.error("profile save failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}
