// EditProfile (§III.N). Editable nickname over the read-only handle.
// The nickname and one of the six official mascot poses can be edited here.
// Saves through /api/users/profile and updates the in-memory session
// immediately. Dirty-state is local because profile data uses a separate
// endpoint from /api/users/settings.

import OSLog
import SwiftUI

struct EditProfileView: View {
    @Environment(AuthService.self) private var auth
    @Environment(\.dismiss) private var dismiss

    @State private var nickname: String = ""
    @State private var pose: MascotPose = .face
    @State private var saving = false
    @State private var error: Error?
    @State private var initialized = false

    private let log = Logger(subsystem: "app.tuji.ios", category: "edit-profile")

    var body: some View {
        ScrollView {
            VStack(spacing: Space.s6) {
                self.heroAvatar
                self.avatarPicker
                self.nicknameField
                self.handleField
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
                    Text(self.saving ? "儲存中…" : "儲存")
                        .font(.system(size: 15, weight: .heavy))
                        .foregroundStyle(self.dirty && !self.saving ? .tujiTeal : .tujiInk4)
                }
                .disabled(!self.dirty || self.saving)
            }
        }
        .onAppear { self.initialize() }
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
            TextField("輸入暱稱", text: self.$nickname)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .font(.tujiBody)
                .padding(.horizontal, Space.s4)
                .padding(.vertical, Space.s3)
                .background(.tujiCard, in: .rect(cornerRadius: Radius.md))
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.md)
                        .stroke(.tujiInk4.opacity(0.25), lineWidth: 1)
                )
            Text("最長 20 字")
                .font(.tujiCaption)
                .foregroundStyle(.tujiInk4)
        }
    }

    private var handleField: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Text("Handle")
                .font(.tujiOverline)
                .tracking(2)
                .foregroundStyle(.tujiInk3)
            Text("@\(self.handleFromAuth)")
                .font(.tujiMono)
                .foregroundStyle(.tujiInk3)
                .padding(.horizontal, Space.s4)
                .padding(.vertical, Space.s3)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.tujiInk4.opacity(0.06), in: .rect(cornerRadius: Radius.md))
            Text("Handle 由系統指派，無法修改")
                .font(.tujiCaption)
                .foregroundStyle(.tujiInk4)
        }
    }

    // MARK: - State

    private var handleFromAuth: String {
        if case let .signedIn(user) = auth.state {
            if let u = user.username, !u.isEmpty { return u }
            if let e = user.email, let local = e.split(separator: "@").first {
                return String(local)
            }
        }
        return "guest"
    }

    private func initialize() {
        guard !self.initialized else { return }
        if case let .signedIn(user) = auth.state {
            self.nickname = user.nickname ?? ""
            // Pose is shown read-only (editing disabled for now).
            self.pose = MascotPose(rawValue: user.avatar ?? "") ?? .face
        }
        self.initialized = true
    }

    private var dirty: Bool {
        if case let .signedIn(user) = auth.state {
            let oldNick = user.nickname ?? ""
            let oldPose = MascotPose(rawValue: user.avatar ?? "") ?? .face
            return self.nickname != oldNick || self.pose != oldPose
        }
        return false
    }

    private func save() async {
        let trimmed = self.nickname.trimmingCharacters(in: .whitespaces)
        guard trimmed.count <= 20 else {
            self.error = NSError(
                domain: "tuji.profile",
                code: 0,
                userInfo: [NSLocalizedDescriptionKey: tujiLocalized("暱稱不能超過 20 字")]
            )
            return
        }
        self.saving = true
        self.error = nil
        defer { self.saving = false }
        let newNickname = trimmed.isEmpty ? nil : trimmed
        let payload = ProfileUpdatePayload(nickname: newNickname, avatar: self.pose.rawValue)
        do {
            let _: ProfileUpdateResponse = try await APIClient.shared.post(
                .usersProfile,
                body: payload
            )
            self.log.info("profile saved")
            self.auth.applyProfile(nickname: newNickname, avatar: self.pose.rawValue)
            self.dismiss()
        } catch {
            self.error = error
            self.log.error("profile save failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}
