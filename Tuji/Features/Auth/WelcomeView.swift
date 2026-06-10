// First screen when not signed in. Apple/Google are W2 follow-ups
// (Apple requires Apple Dev; Google needs UIKit presenting VC bridge).

import SwiftUI

struct WelcomeView: View {
    enum Route: Hashable { case signup, signin }

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
            Mascot(pose: .wave, size: 96)
                .padding(.bottom, Space.s4)
            HStack(spacing: 0) {
                Text("Tuji")
                Text(".").foregroundStyle(.tujiCoral)
            }
            .font(.tujiH1)
            .foregroundStyle(.tujiInk)
            Text("用圖學英文")
                .font(.tujiBodyLg)
                .foregroundStyle(.tujiInk3)
                .padding(.top, Space.s2)
            Spacer()

            VStack(spacing: Space.s3) {
                disabledOAuthBtn(
                    title: "繼續使用 Apple",
                    icon: "applelogo",
                    bg: .tujiInk,
                    fg: .white,
                    note: "（待 Apple Developer Program 通過）"
                )
                disabledOAuthBtn(
                    title: "繼續使用 Google",
                    icon: "g.circle",
                    bg: .tujiCard,
                    fg: .tujiInk,
                    note: "（W2 跟進中）"
                )

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
            }
            .padding(.horizontal, Space.s6)
            .padding(.bottom, Space.s8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.tujiBg)
    }

    @ViewBuilder
    private func disabledOAuthBtn(title: String, icon: String, bg: Color, fg: Color, note: String) -> some View {
        VStack(spacing: 4) {
            HStack(spacing: Space.s2) {
                Image(systemName: icon)
                Text(title)
            }
            .font(.system(size: 15, weight: .heavy))
            .foregroundStyle(fg)
            .padding(.vertical, Space.s4)
            .frame(maxWidth: .infinity)
            .background(bg, in: .rect(cornerRadius: Radius.lg))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.lg)
                    .stroke(.tujiInk4.opacity(0.25), lineWidth: 1)
            )
            .opacity(0.4)
            Text(note).font(.tujiCaption).foregroundStyle(.tujiInk4)
        }
    }
}

#Preview {
    WelcomeView().environment(AuthService.shared)
}
