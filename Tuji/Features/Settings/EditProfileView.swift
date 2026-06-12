// EditProfile (§III.N). Username text field + Mascot pose picker grid.
// Saves via POST /api/users/profile. Dirty-state is local to this view
// (independent of SettingsStore) because the profile endpoint is
// separate from /api/users/settings.

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
                self.poseGrid
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
        ZStack {
            Circle().fill(.tujiTealSoft)
            Mascot(pose: self.pose, size: 56)
        }
        .frame(width: 96, height: 96)
        .frame(maxWidth: .infinity)
    }

    private var poseGrid: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Text("選一個姿勢")
                .font(.tujiCaption)
                .foregroundStyle(.tujiInk3)
                .frame(maxWidth: .infinity, alignment: .center)
            HStack(spacing: Space.s2) {
                ForEach(MascotPose.allCases, id: \.self) { p in
                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        self.pose = p
                    } label: {
                        Mascot(pose: p, size: 36)
                            .frame(width: 56, height: 56)
                            .background(.tujiCard, in: .circle)
                            .overlay(
                                Circle().stroke(
                                    self.pose == p ? Color.tujiTeal : .tujiInk4.opacity(0.25),
                                    lineWidth: self.pose == p ? 3 : 1
                                )
                            )
                    }
                    .buttonStyle(.plain)
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
            self.nickname = user.username ?? ""
            self.pose = MascotPose(rawValue: user.avatar ?? "") ?? .face
        }
        self.initialized = true
    }

    private var dirty: Bool {
        if case let .signedIn(user) = auth.state {
            let oldNick = user.username ?? ""
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
                userInfo: [NSLocalizedDescriptionKey: "暱稱不能超過 20 字"]
            )
            return
        }
        self.saving = true
        self.error = nil
        defer { self.saving = false }
        let payload = ProfileUpdatePayload(
            nickname: trimmed.isEmpty ? nil : trimmed,
            avatar: self.pose.rawValue
        )
        do {
            let _: ProfileUpdateResponse = try await APIClient.shared.post(
                .usersProfile,
                body: payload
            )
            self.log.info("profile saved")
            // Refresh session so SessionUser picks up the new values
            await self.auth.restoreSession()
            self.dismiss()
        } catch {
            self.error = error
            self.log.error("profile save failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}
