// First screen when not signed in. Offers Apple / Google / Email sign-in
// plus a guest entry point.

import SwiftUI

struct WelcomeView: View {
    enum Route: Hashable { case signup, signin }

    @Environment(AuthService.self) private var auth
    @State private var path: [Route] = []

    var body: some View {
        NavigationStack(path: $path) {
            content
                .navigationDestination(for: Route.self) { route in
                    switch route {
                    case .signup: SignupView(path: $path)
                    case .signin: SigninView(path: $path)
                    }
                }
        }
    }

    private var content: some View {
        VStack(spacing: 0) {
            // Reached from inside guest mode (Me tab / Today hero) this screen
            // is a root swap, not a push — without an explicit way back it's a
            // dead end for an accidental tap.
            if auth.cameFromGuest {
                HStack {
                    Button {
                        auth.enterGuestMode()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.tujiIcon(16, weight: .semibold))
                            .foregroundStyle(.tujiInk2)
                            .padding(Space.s3)
                            .background(.tujiPaper, in: .circle)
                            .overlay(Circle().stroke(.tujiRule.opacity(0.3), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    Spacer()
                }
                .padding(.horizontal, Space.s4)
                .padding(.top, Space.s3)
            }
            Spacer()
            TujiBrandLockup(scale: 0.88)
            Spacer()

            VStack(spacing: Space.s3) {
                AppleSignInButton()

                Button {
                    Task { await auth.signInWithGoogle() }
                } label: {
                    HStack(spacing: Space.s2) {
                        Image(systemName: "g.circle.fill")
                            .foregroundStyle(.tujiInk)
                        Text(auth.loading ? LocalizedStringKey("Google 登入中...") : LocalizedStringKey("繼續使用 Google"))
                            .foregroundStyle(.tujiInk)
                    }
                    .font(.tujiBodySm(.strong))
                    .padding(.vertical, Space.s3)
                    .frame(maxWidth: .infinity)
                    .background(.tujiPaper, in: .rect(cornerRadius: Radius.r0))
                    .overlay(
                        RoundedRectangle(cornerRadius: Radius.r0)
                            .stroke(.tujiRule.opacity(0.25), lineWidth: 1)
                    )
                }
                .disabled(auth.loading)

                if let err = auth.error {
                    Text(err)
                        .font(.tujiLabel)
                        .foregroundStyle(.tujiAlert)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, Space.s3)
                }

                Button {
                    path.append(.signup)
                } label: {
                    Text("使用 Email")
                        .font(.tujiBodySm(.strong))
                        .foregroundStyle(.tujiBrandSecondary)
                        .padding(.vertical, Space.s3)
                        .frame(maxWidth: .infinity)
                        .background(Color.tujiBrandPrimary.opacity(0.18), in: .rect(cornerRadius: Radius.r0))
                }

                Button {
                    path.append(.signin)
                } label: {
                    Text("已有帳號？登入")
                        .font(.tujiBodySm(.strong))
                        .foregroundStyle(.tujiInk3)
                }
                .padding(.top, Space.s2)

                Button {
                    auth.enterGuestMode()
                } label: {
                    // Someone who *left* guest mode to get here isn't choosing
                    // a mode — they're going back.
                    Text(auth.cameFromGuest ? LocalizedStringKey("返回訪客模式") : LocalizedStringKey("先逛逛 → 訪客模式"))
                        .font(.tujiLabel)
                        .foregroundStyle(.tujiInk3)
                }
            }
            // Cap the auth button column so all buttons share one width and
            // stay under ASAuthorizationAppleIDButton's built-in 375pt max —
            // otherwise on large phones (e.g. 16 Pro Max: 440 − 48 padding =
            // 392 > 375) the Apple button logs an Auto Layout conflict.
            .frame(maxWidth: 360)
            .padding(.horizontal, Space.s4)
            .padding(.bottom, Space.s5)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.tujiPaper)
    }
}

#Preview {
    WelcomeView().environment(AuthService.shared)
}
