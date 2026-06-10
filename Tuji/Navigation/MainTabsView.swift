// W2 placeholder for the post-login surface. Real 5-tab layout (Today /
// Cards / Tuji / Progress / Me) comes online in W4.
//
// Current scope: prove the Bearer chain end-to-end — show the signed-in
// user, hit /api/test_smoke/whoami with their access token, and offer
// sign-out.

import SwiftUI

struct MainTabsView: View {
    let user: SessionUser
    @Environment(AuthService.self) private var auth

    @State private var pinging = false
    @State private var lastResult: SmokeTest.Result?

    var body: some View {
        VStack(spacing: 0) {
            // Hero
            VStack(spacing: Space.s4) {
                Mascot(pose: .cheer, size: 88)

                VStack(spacing: Space.s1) {
                    HStack(spacing: 0) {
                        Text("早安，")
                        Text(displayName).foregroundStyle(.tujiTeal)
                    }
                    .font(.tujiH2)
                    .foregroundStyle(.tujiInk)

                    Text(user.email ?? "—")
                        .font(.tujiCaption)
                        .foregroundStyle(.tujiInk3)

                    Text("uid \(user.id.uuidString.prefix(8))")
                        .font(.tujiMono)
                        .foregroundStyle(.tujiInk4)
                }
            }
            .padding(.top, Space.s12)

            Spacer()

            // Smoke test card
            VStack(spacing: Space.s4) {
                BBtn(
                    title: pinging ? "驗證中..." : "Bearer smoke test",
                    fullWidth: false,
                    icon: "antenna.radiowaves.left.and.right",
                    action: ping
                )
                .frame(maxWidth: 280)
                .disabled(pinging)

                if let r = lastResult {
                    resultCard(r)
                }
            }

            Spacer()

            Button {
                Task { await auth.signOut() }
            } label: {
                Text("登出")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.tujiCoral)
                    .padding(.vertical, Space.s3)
                    .padding(.horizontal, Space.s5)
                    .background(.tujiCoral.opacity(0.08), in: .rect(cornerRadius: Radius.pill))
            }
            .padding(.bottom, Space.s8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.tujiBg)
    }

    private var displayName: String {
        if let u = user.username, !u.isEmpty { return u }
        if let e = user.email, let local = e.split(separator: "@").first { return String(local) }
        return "Tuji 探險者"
    }

    @ViewBuilder
    private func resultCard(_ r: SmokeTest.Result) -> some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack(spacing: Space.s2) {
                Image(systemName: r.status == 200 ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .foregroundStyle(r.status == 200 ? .tujiGreen : .tujiCoral)
                Text("HTTP \(r.status)")
                    .font(.tujiOverline)
                    .foregroundStyle(.tujiInk2)
            }
            Text(r.body)
                .font(.tujiMono)
                .foregroundStyle(.tujiInk2)
                .multilineTextAlignment(.leading)
        }
        .padding(Space.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.tujiCard, in: .rect(cornerRadius: Radius.lg))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg)
                .stroke(.tujiInk4.opacity(0.25), lineWidth: 1)
        )
        .padding(.horizontal, Space.s6)
    }

    private func ping() {
        Task {
            pinging = true
            defer { pinging = false }
            do {
                let token = try await auth.validAccessToken()
                lastResult = await SmokeTest.whoami(bearer: token)
            } catch {
                lastResult = SmokeTest.Result(
                    status: -1,
                    body: "Token error: \(error.localizedDescription)"
                )
            }
        }
    }
}

#Preview {
    MainTabsView(
        user: SessionUser.preview
    )
    .environment(AuthService.shared)
}

extension SessionUser {
    fileprivate static var preview: SessionUser {
        // Build a fake user just for previews. Init(from:) requires a real
        // Supabase.User so we reach for the memberwise init via JSON decode.
        let json = """
        {"id":"00000000-0000-0000-0000-000000000000","email":"preview@tuji.dev"}
        """.data(using: .utf8)!
        // swiftlint:disable:next force_try
        let user = try! JSONDecoder().decode(StubUser.self, from: json)
        return SessionUser(
            id: user.id,
            email: user.email,
            username: "rex",
            avatar: nil
        )
    }

    private init(id: UUID, email: String?, username: String?, avatar: String?) {
        self.id = id; self.email = email; self.username = username; self.avatar = avatar
    }

    private struct StubUser: Codable { let id: UUID; let email: String? }
}
