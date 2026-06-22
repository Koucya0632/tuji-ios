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
                        Text(auth.loading ? "Google 登入中..." : "繼續使用 Google")
                            .foregroundStyle(.tujiInk)
                    }
                    .font(.system(size: 15, weight: .heavy))
                    .padding(.vertical, Space.s4)
                    .frame(maxWidth: .infinity)
                    .background(.tujiCard, in: .rect(cornerRadius: Radius.lg))
                    .overlay(
                        RoundedRectangle(cornerRadius: Radius.lg)
                            .stroke(.tujiInk4.opacity(0.25), lineWidth: 1)
                    )
                }
                .disabled(auth.loading)

                if let err = auth.error {
                    Text(err)
                        .font(.tujiCaption)
                        .foregroundStyle(.tujiCoral)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, Space.s4)
                }

                Button {
                    path.append(.signup)
                } label: {
                    Text("使用 Email")
                        .font(.system(size: 15, weight: .heavy))
                        .foregroundStyle(.tujiTeal)
                        .padding(.vertical, Space.s4)
                        .frame(maxWidth: .infinity)
                        .background(.tujiTealSoft, in: .rect(cornerRadius: Radius.lg))
                }

                Button {
                    path.append(.signin)
                } label: {
                    Text("已有帳號？登入")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.tujiInk3)
                }
                .padding(.top, Space.s2)

                Button {
                    auth.enterGuestMode()
                } label: {
                    Text("先逛逛 → 訪客模式")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.tujiInk4)
                }
            }
            .padding(.horizontal, Space.s6)
            .padding(.bottom, Space.s8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.tujiBg)
    }
}

#Preview {
    WelcomeView().environment(AuthService.shared)
}
