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
                VStack(alignment: .leading, spacing: Space.s4) {
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
                            .padding(Space.s3)
                            .background(.tujiPaper, in: .rect(cornerRadius: Radius.r0))
                            .overlay(
                                RoundedRectangle(cornerRadius: Radius.r0)
                                    .stroke(.tujiRule.opacity(0.25), lineWidth: 1)
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
                        .padding(Space.s3)
                        .background(.tujiPaper, in: .rect(cornerRadius: Radius.r0))
                        .overlay(
                            RoundedRectangle(cornerRadius: Radius.r0)
                                .stroke(.tujiRule.opacity(0.25), lineWidth: 1)
                        )
                    }

                    if let err = auth.error {
                        HStack(alignment: .top, spacing: Space.s2) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.tujiAlert)
                            Text(err)
                                .font(.tujiBodySm)
                                .foregroundStyle(.tujiInk2)
                        }
                        .padding(Space.s3)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.tujiAlert.opacity(0.08), in: .rect(cornerRadius: Radius.r0))
                    }
                }
                .padding(.horizontal, Space.s4)
                .padding(.top, Space.s4)
            }

            VStack(spacing: Space.s3) {
                BBtn(
                    title: auth.loading ? "登入中..." : "登入",
                    bg: canSubmit ? .tujiEye : .tujiPaper3,
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
                    .font(.tujiBodySm)
                }
            }
            .padding(.horizontal, Space.s4)
            .padding(.vertical, Space.s4)
        }
        .background(.tujiPaper)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.tujiPaper, for: .navigationBar)
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
