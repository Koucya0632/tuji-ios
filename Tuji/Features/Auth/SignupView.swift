// Email signup form. On success, AuthService.state flips to .signedIn
// and RootView swaps to MainTabsView automatically.
//
// If the dev Supabase project has email confirmation ON (default), the
// returned response has no session — we surface "check your inbox" via
// auth.error and keep the form visible.

import SwiftUI

struct SignupView: View {
    @Environment(AuthService.self) private var auth
    @Binding var path: [WelcomeView.Route]

    @State private var email = ""
    @State private var password = ""
    @State private var username = ""
    @State private var showPwd = false
    @State private var showEmailConfirmation = false

    private var trimmedEmail: String {
        email.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var trimmedUsername: String {
        username.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var passwordUsesAllowedCharacters: Bool {
        password.unicodeScalars.allSatisfy { scalar in
            (33...126).contains(scalar.value)
        }
    }

    private var canSubmit: Bool {
        trimmedEmail.contains("@") &&
            password.count >= 8 &&
            passwordUsesAllowedCharacters &&
            !trimmedUsername.isEmpty &&
            !auth.loading
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: Space.s5) {
                    VStack(alignment: .leading, spacing: Space.s2) {
                        Text("建立帳號")
                            .font(.tujiH2)
                            .foregroundStyle(.tujiInk)

                        Text("填入登入信箱、密碼和顯示名稱，開始建立你的單字卡。")
                            .font(.tujiBody)
                            .foregroundStyle(.tujiInk3)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    field(
                        label: "Email",
                        text: $email,
                        placeholder: "name@example.com",
                        keyboard: .emailAddress,
                        contentType: .emailAddress,
                        capitalize: false,
                        helper: "用來登入與接收驗證信"
                    )

                    passwordField

                    field(
                        label: "暱稱",
                        text: $username,
                        placeholder: "想讓大家怎麼稱呼你",
                        keyboard: .default,
                        contentType: .username,
                        capitalize: true,
                        helper: "之後可以在個人設定中修改"
                    )

                    if let err = auth.error {
                        HStack(alignment: .top, spacing: Space.s2) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.tujiCoral)
                            Text(err)
                                .font(.tujiBody)
                                .foregroundStyle(.tujiInk2)
                        }
                        .padding(Space.s4)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.tujiCoral.opacity(0.08), in: .rect(cornerRadius: Radius.md))
                    }
                }
                .padding(.horizontal, Space.s6)
                .padding(.top, Space.s5)
            }

            VStack(spacing: Space.s3) {
                BBtn(
                    title: auth.loading ? "建立中..." : "建立帳號",
                    bg: canSubmit ? .tujiTeal : .tujiInk4,
                    fg: .white,
                    fullWidth: true,
                    action: submit
                )
                .disabled(!canSubmit)

                Button {
                    path = [.signin]
                } label: {
                    HStack(spacing: 4) {
                        Text("已有帳號？")
                            .foregroundStyle(.tujiInk3)
                        Text("登入")
                            .foregroundStyle(.tujiTeal)
                    }
                    .font(.tujiBody)
                }
            }
            .padding(.horizontal, Space.s6)
            .padding(.vertical, Space.s5)
        }
        .background(.tujiBg)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.tujiBg, for: .navigationBar)
        .alert("確認信已寄出", isPresented: $showEmailConfirmation) {
            Button("前往登入") {
                path = [.signin]
            }
        } message: {
            Text("請開信箱點擊驗證連結，完成後再用這組 Email 和密碼登入。")
        }
    }

    private var passwordField: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Text("密碼")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.tujiInk2)

            HStack {
                Group {
                    if showPwd {
                        TextField("至少 8 個字元", text: $password)
                    } else {
                        SecureField("至少 8 個字元", text: $password)
                    }
                }
                .textContentType(.newPassword)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)

                Button { showPwd.toggle() } label: {
                    Image(systemName: showPwd ? "eye.slash" : "eye")
                        .foregroundStyle(.tujiInk3)
                }
            }
            .padding(Space.s4)
            .background(.tujiCard, in: .rect(cornerRadius: Radius.md))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.md)
                    .stroke(.tujiInk4.opacity(0.25), lineWidth: 1)
            )

            if password
                .contains(where: { !$0.unicodeScalars.allSatisfy { scalar in (33...126).contains(scalar.value) } })
            {
                Text("密碼只能使用英文、數字或符號")
                    .font(.tujiCaption)
                    .foregroundStyle(.tujiCoral)
            } else if password.isEmpty {
                Text("至少 8 個字元，英文、數字或符號皆可")
                    .font(.tujiCaption)
                    .foregroundStyle(.tujiInk4)
            } else if password.count < 8 {
                Text("還差 \(8 - password.count) 個字元")
                    .font(.tujiCaption)
                    .foregroundStyle(.tujiInk4)
            }
        }
    }

    private func field(
        label: String,
        text: Binding<String>,
        placeholder: String,
        keyboard: UIKeyboardType,
        contentType: UITextContentType,
        capitalize: Bool,
        helper: String? = nil
    )
        -> some View
    {
        VStack(alignment: .leading, spacing: Space.s2) {
            Text(label)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.tujiInk2)

            TextField(placeholder, text: text)
                .keyboardType(keyboard)
                .textContentType(contentType)
                .textInputAutocapitalization(capitalize ? .words : .never)
                .autocorrectionDisabled(!capitalize)
                .padding(Space.s4)
                .background(.tujiCard, in: .rect(cornerRadius: Radius.md))
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.md)
                        .stroke(.tujiInk4.opacity(0.25), lineWidth: 1)
                )

            if let helper {
                Text(helper)
                    .font(.tujiCaption)
                    .foregroundStyle(.tujiInk4)
            }
        }
    }

    private func submit() {
        Task {
            let result = await auth.signUp(email: trimmedEmail, password: password, username: trimmedUsername)
            if result == .pendingEmailConfirmation {
                showEmailConfirmation = true
            }
        }
    }
}

#Preview {
    @Previewable @State var path: [WelcomeView.Route] = [.signup]
    return NavigationStack(path: $path) {
        SignupView(path: $path).environment(AuthService.shared)
    }
}
