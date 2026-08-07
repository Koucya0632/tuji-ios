// Email signup form. On success, AuthService.state flips to .signedIn
// and RootView swaps to MainTabsView automatically.
//
// If the dev Supabase project has email confirmation ON (default), the
// returned response has no session — we surface "check your inbox" via
// auth.error and keep the form visible.

import SwiftUI

struct SignupView: View {
    /// See `SigninView` — same pinned-footer layout, same keyboard trap, and
    /// worse here because this form is taller. Focus is modelled so Return
    /// walks Email → 密碼 → submit instead of dismissing the keyboard.
    private enum Field: Hashable {
        case email
        case password
    }

    @Environment(AuthService.self) private var auth
    @Binding var path: [WelcomeView.Route]

    @State private var email = ""
    @State private var password = ""
    @State private var showPwd = false
    @State private var showEmailConfirmation = false
    @FocusState private var focused: Field?

    private var trimmedEmail: String {
        email.trimmingCharacters(in: .whitespacesAndNewlines)
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
            !auth.loading
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: Space.s4) {
                        VStack(alignment: .leading, spacing: Space.s2) {
                            Text("建立帳號")
                                .font(.tujiH2)
                                .foregroundStyle(.tujiInk)

                            Text("填入登入信箱和密碼，開始建立你的單字卡。")
                                .font(.tujiBodySm)
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
                        .id(Field.email)

                        passwordField
                            .id(Field.password)

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
                    .padding(.bottom, Space.s4)
                }
                .scrollDismissesKeyboard(.interactively)
                .onChange(of: focused) { _, field in
                    guard let field else { return }
                    withAnimation(.easeOut(duration: 0.2)) {
                        proxy.scrollTo(field, anchor: .center)
                    }
                }
            }

            VStack(spacing: Space.s3) {
                BBtn(
                    title: auth.loading ? "建立中..." : "建立帳號",
                    bg: canSubmit ? .tujiEye : .tujiPaper3,
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
                    .font(.tujiBodySm)
                }
            }
            .padding(.horizontal, Space.s4)
            .padding(.vertical, Space.s4)
        }
        .background(.tujiPaper)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.tujiPaper, for: .navigationBar)
        .onSubmit {
            switch focused {
            case .email: focused = .password
            case .password where canSubmit: submit()
            default: focused = nil
            }
        }
        .tujiPrompt(
            isPresented: $showEmailConfirmation,
            style: .success,
            title: "確認信已寄出",
            message: "請開信箱點擊驗證連結，完成後再用這組 Email 和密碼登入。",
            primary: TujiPromptAction("前往登入") {
                path = [.signin]
            }
        )
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
                .focused($focused, equals: .password)
                .submitLabel(.go)
                .accessibilityLabel(Text("密碼"))

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

            if password
                .contains(where: { !$0.unicodeScalars.allSatisfy { scalar in (33...126).contains(scalar.value) } })
            {
                Text("密碼只能使用英文、數字或符號")
                    .font(.tujiLabel)
                    .foregroundStyle(.tujiAlert)
            } else if password.isEmpty {
                Text("至少 8 個字元，英文、數字或符號皆可")
                    .font(.tujiLabel)
                    .foregroundStyle(.tujiInk3)
            } else if password.count < 8 {
                Text("還差 \(8 - password.count) 個字元")
                    .font(.tujiLabel)
                    .foregroundStyle(.tujiInk3)
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
                .focused($focused, equals: .email)
                .submitLabel(.next)
                .accessibilityLabel(Text(label))
                .padding(Space.s3)
                .background(.tujiPaper, in: .rect(cornerRadius: Radius.r0))
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.r0)
                        .stroke(.tujiRule.opacity(0.25), lineWidth: 1)
                )

            if let helper {
                Text(helper)
                    .font(.tujiLabel)
                    .foregroundStyle(.tujiInk3)
            }
        }
    }

    private func submit() {
        focused = nil
        Task {
            let result = await auth.signUp(email: trimmedEmail, password: password)
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
