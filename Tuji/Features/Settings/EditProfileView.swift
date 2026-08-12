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

    @State private var vm = EditProfileVM()
    /// The cropped photo as an image — preview only. The bytes that get
    /// uploaded live on the view model, because they are what makes the form
    /// dirty.
    @State private var pendingAvatarImage: UIImage?
    @State private var avatarIntake = ImageIntake(encoding: .profile, crop: .square(mask: .circle))

    var body: some View {
        VStack(spacing: 0) {
            TujiNavBar(leading: .back) {
                TujiNavTextAction(
                    title: self.vm.saving ? "儲存中…" : "儲存",
                    isEnabled: self.vm.canSave
                ) {
                    Task { await self.saveAndDismiss() }
                }
            }
            self.form
        }
        .background(.tujiPaper)
        .navigationTitle("編輯個人資料")
        .toolbar(.hidden, for: .navigationBar)
        .task {
            self.connectAvatarIntake()
            await self.vm.load(session: self.sessionUser)
        }
        .imageIntake(
            self.avatarIntake,
            title: "更換頭像",
            extraChoices: self.vm.hasCustomAvatar
                ? [ImageIntakeChoice("使用預設黑貓頭像") {
                    self.vm.useDefaultAvatar()
                    self.pendingAvatarImage = nil
                }]
                : []
        )
    }

    private var form: some View {
        ScrollView {
            VStack(spacing: Space.s4) {
                self.heroAvatar
                self.nicknameField
                self.bioField
                self.uidField
                if let message = self.vm.error?.localizedDescription ?? self.avatarIntake.errorMessage {
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
    private func connectAvatarIntake() {
        self.avatarIntake.onDeliver { data in
            guard let image = UIImage(data: data) else { return .rejected(nil) }
            self.vm.stageAvatar(data: data)
            self.pendingAvatarImage = image
            return .accepted
        }
    }

    private var heroAvatar: some View {
        Button {
            self.avatarIntake.begin()
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
                                .overlay(Circle().stroke(.tujiCurrent, lineWidth: 2))
                                .shadow(color: .black.opacity(0.08), radius: 10, x: 0, y: 4)
                        } else {
                            ProfileAvatar(avatar: self.vm.avatar, size: 104, selected: true)
                        }
                    }

                    Image(systemName: "camera.fill")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.tujiInk)
                        .frame(width: 34, height: 34)
                        .background(.tujiBrandPrimary, in: .circle)
                        .overlay(Circle().stroke(.tujiPaper, lineWidth: 3))
                }
                Text("點一下更換頭像")
                    .font(.tujiLabel)
                    .foregroundStyle(.tujiInk3)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
        .disabled(self.vm.saving || self.vm.loading)
        .accessibilityLabel("更換頭像")
    }

    private var nicknameField: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Text("暱稱")
                .font(.tujiLabel)
                .tracking(2)
                .foregroundStyle(.tujiInk3)
            TextField("大家會怎麼稱呼你", text: self.$vm.nickname)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .font(.tujiBodySm)
                .padding(.horizontal, Space.s3)
                .padding(.vertical, Space.s3)
                .background(.tujiPaper, in: .rect(cornerRadius: Radius.r0))
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.r0)
                        .stroke(
                            self.vm.nicknameIsValid ? .tujiRule : Color.tujiAlert,
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
            TextField("介紹一下你自己", text: self.$vm.bio, axis: .vertical)
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
                            self.vm.bioIsValid ? .tujiRule : Color.tujiAlert,
                            lineWidth: 1
                        )
                )
            HStack {
                Text("不能放網址或個人資訊")
                    .font(.tujiLabel)
                    .foregroundStyle(.tujiInk3)
                Spacer()
                Text(verbatim: "\(EditProfileVM.bioMax - self.vm.trimmedBio.count)")
                    .font(.tujiLabel)
                    .foregroundStyle(self.vm.bioIsValid ? .tujiInk3 : .tujiAlert)
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
        if let serverUid = self.vm.serverUid, !serverUid.isEmpty { return serverUid }
        if case let .signedIn(user) = auth.state, let uid = user.username, !uid.isEmpty {
            return uid
        }
        return "—"
    }

    private var sessionUser: SessionUser? {
        if case let .signedIn(user) = self.auth.state { return user }
        return nil
    }

    /// The VM does the write and hands back the identity; mirroring it into the
    /// session and dismissing are the View's job (a view model does not reach
    /// `AuthService`).
    private func saveAndDismiss() async {
        guard let saved = await self.vm.save() else { return }
        self.auth.applyProfile(nickname: saved.nickname, avatar: saved.avatar)
        self.dismiss()
    }
}
