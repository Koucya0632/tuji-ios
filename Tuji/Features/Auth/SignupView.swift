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

    private var canSubmit: Bool {
        email.contains("@") && password.count >= 8 && !username.isEmpty && !auth.loading
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: Space.s5) {
                    Text("建立帳號")
                        .font(.tujiH2)
                        .foregroundStyle(.tujiInk)

                    field(
                        label: "Email",
                        text: $email,
                        placeholder: "you@example.com",
                        keyboard: .emailAddress,
                        contentType: .emailAddress,
                        capitalize: false
                    )

                    passwordField

                    field(
                        label: "暱稱",
                        text: $username,
                        placeholder: "Rex",
                        keyboard: .default,
                        contentType: .username,
                        capitalize: true
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
    }

    private var passwordField: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Text("密碼")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.tujiInk2)

            HStack {
                Group {
                    if showPwd {
                        TextField("8 字以上", text: $password)
                    } else {
                        SecureField("8 字以上", text: $password)
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

            // The placeholder already says 8 字以上 — repeating it below was
            // noise. Only speak up while the rule is actually unmet.
            if !password.isEmpty, password.count < 8 {
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
        capitalize: Bool
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
        }
    }

    private func submit() {
        Task {
            await auth.signUp(email: email, password: password, username: username)
        }
    }
}

#Preview {
    @Previewable @State var path: [WelcomeView.Route] = [.signup]
    return NavigationStack(path: $path) {
        SignupView(path: $path).environment(AuthService.shared)
    }
}
