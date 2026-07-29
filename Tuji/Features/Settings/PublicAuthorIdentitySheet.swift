// 公開作者身分 —— the one-time consent step before anything is published, and
// the edit screen afterwards.
//
// Why it exists (docs/COMMUNITY_ATLAS_PLAN.md §3B): 暱稱 and handle were built
// as private fields. The 暱稱 is filled in automatically from the name Apple
// hands over at first sign-in, and handles used to be the first half of the
// email address. Publishing either without asking would put a real name on the
// public wall. So this screen states exactly what becomes public, and the
// server refuses to publish until the user has accepted it here.

import SwiftUI

struct PublicAuthorIdentitySheet: View {
    @State private var vm: PublicAuthorIdentityVM
    @Environment(\.dismiss) private var dismiss

    /// Called after a successful save, so the caller can continue whatever it
    /// was gating (publishing an item or a collection).
    private let onConfirmed: () -> Void

    init(identity: PublicAuthorIdentity, onConfirmed: @escaping () -> Void = {}) {
        _vm = State(initialValue: PublicAuthorIdentityVM(identity: identity))
        self.onConfirmed = onConfirmed
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Space.s5) {
                    self.intro
                    if !self.vm.isEditable { self.cooldownNotice }
                    self.displayNameField
                    self.handleField
                    if let message = self.vm.errorMessage {
                        Text(message)
                            .font(.tujiCaption)
                            .foregroundStyle(.tujiCoral)
                    }
                    BBtn(
                        title: self.vm.isSaving
                            ? "儲存中…"
                            : (self.vm.isFirstTime ? "確認並公開" : "儲存"),
                        bg: .tujiTeal,
                        fg: .white,
                        fullWidth: true,
                        icon: "checkmark"
                    ) {
                        Task {
                            if await self.vm.save() {
                                self.onConfirmed()
                                self.dismiss()
                            }
                        }
                    }
                    .disabled(!self.vm.canSubmit)
                    .opacity(self.vm.canSubmit ? 1 : 0.5)
                }
                .padding(.horizontal, Space.s6)
                .padding(.vertical, Space.s5)
            }
            .background(.tujiBg)
            .navigationTitle("公開作者身分")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("取消") { self.dismiss() }
                        .foregroundStyle(.tujiInk3)
                }
            }
        }
    }

    private var intro: some View {
        HStack(alignment: .top, spacing: Space.s3) {
            MascotAvatar(pose: MascotPose(rawValue: self.vm.avatar) ?? .face, size: 48)
            VStack(alignment: .leading, spacing: 4) {
                Text("公開後，其他人會看到你的頭像、顯示名稱和帳號代碼。")
                    .font(.tujiCaption)
                    .foregroundStyle(.tujiInk2)
                Text("你的 email 不會公開。")
                    .font(.tujiCaption)
                    .foregroundStyle(.tujiInk3)
            }
        }
        .padding(Space.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.tujiCard, in: .rect(cornerRadius: Radius.md))
    }

    /// Shown instead of letting someone retype their name and only then be
    /// refused by the server. A rename rewrites the byline on everything they
    /// ever published, which is why it is limited at all.
    private var cooldownNotice: some View {
        HStack(alignment: .top, spacing: Space.s3) {
            Image(systemName: "clock.badge.exclamationmark")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.tujiCoral)
            VStack(alignment: .leading, spacing: 2) {
                Text("公開身分暫時無法修改")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.tujiInk)
                if let date = self.vm.nextChangeText {
                    Text("\(date) 之後可以再修改一次。")
                        .font(.tujiCaption)
                        .foregroundStyle(.tujiInk3)
                }
                Text("改名會一併改掉你已公開內容上的署名，所以有間隔限制。")
                    .font(.tujiCaption)
                    .foregroundStyle(.tujiInk3)
            }
        }
        .padding(Space.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.tujiCoral.opacity(0.08), in: .rect(cornerRadius: Radius.md))
    }

    private var displayNameField: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Text("顯示名稱")
                .font(.tujiOverline)
                .tracking(2)
                .foregroundStyle(.tujiInk3)
            TextField("大家會怎麼稱呼你", text: self.$vm.displayName)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .disabled(!self.vm.isEditable)
                .font(.tujiBody)
                .padding(.horizontal, Space.s4)
                .padding(.vertical, Space.s3)
                .background(.tujiCard, in: .rect(cornerRadius: Radius.md))
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.md)
                        .stroke(.tujiInk4.opacity(0.25), lineWidth: 1)
                )
            Text("最長 20 字，之後可以修改")
                .font(.tujiCaption)
                .foregroundStyle(.tujiInk4)
        }
    }

    private var handleField: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Text("帳號代碼")
                .font(.tujiOverline)
                .tracking(2)
                .foregroundStyle(.tujiInk3)
            HStack(spacing: 2) {
                Text(verbatim: "@")
                    .font(.tujiMono)
                    .foregroundStyle(.tujiInk4)
                TextField("handle", text: self.$vm.handle)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .disabled(!self.vm.isEditable)
                    .font(.tujiMono)
            }
            .padding(.horizontal, Space.s4)
            .padding(.vertical, Space.s3)
            .background(.tujiCard, in: .rect(cornerRadius: Radius.md))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.md)
                    .stroke(.tujiInk4.opacity(0.25), lineWidth: 1)
            )
            Text("2–40 字，只能用英數字、_ . -，不可重複")
                .font(.tujiCaption)
                .foregroundStyle(.tujiInk4)
        }
    }
}

#Preview {
    PublicAuthorIdentitySheet(
        identity: PublicAuthorIdentity(
            confirmed: false,
            handle: "tuji-8f3a2c1d9b4e",
            displayName: "",
            avatar: "face",
            canChange: true,
            nextChangeAt: nil
        )
    )
}
