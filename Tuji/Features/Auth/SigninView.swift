// Email signin form. On success RootView swaps to MainTabsView.

import SwiftUI

struct SigninView: View {
    @Environment(AuthService.self) private var auth
    @Binding var path: [WelcomeView.Route]

    @State private var email = ""
    @State private var password = ""
    @State private var showPwd = false

    private var canSubmit: Bool {
        email.contains("@") && !password.isEmpty && !auth.loading
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: Space.s5) {
                    Text("登入")
                        .font(.tujiH2)
                        .foregroundStyle(.tujiInk)

                    VStack(alignment: .leading, spacing: Space.s2) {
                        Text("Email")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(.tujiInk2)
                        TextField("", text: $email)
                            .keyboardType(.emailAddress)
                            .textContentType(.emailAddress)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .padding(Space.s4)
                            .background(.tujiCard, in: .rect(cornerRadius: Radius.md))
                            .overlay(
                                RoundedRectangle(cornerRadius: Radius.md)
                                    .stroke(.tujiInk4.opacity(0.25), lineWidth: 1)
                            )
                    }

                    VStack(alignment: .leading, spacing: Space.s2) {
                        Text("密碼")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(.tujiInk2)
                        HStack {
                            Group {
                                if showPwd {
                                    TextField("", text: $password)
                                } else {
                                    SecureField("", text: $password)
                                }
                            }
                            .textContentType(.password)
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
                    }

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
                    title: auth.loading ? "登入中..." : "登入",
                    bg: canSubmit ? .tujiTeal : .tujiInk4,
                    fg: .white,
                    fullWidth: true,
                    action: submit
                )
                .disabled(!canSubmit)

                Button {
                    path = [.signup]
                } label: {
                    HStack(spacing: 4) {
                        Text("沒有帳號？")
                            .foregroundStyle(.tujiInk3)
                        Text("註冊")
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

    private func submit() {
        Task { await auth.signIn(email: email, password: password) }
    }
}

#Preview {
    @Previewable @State var path: [WelcomeView.Route] = [.signin]
    return NavigationStack(path: $path) {
        SigninView(path: $path).environment(AuthService.shared)
    }
}
