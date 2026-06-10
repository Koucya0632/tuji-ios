// W2 placeholder for the post-login surface. Real 5-tab layout (Today /
// Cards / Tuji / Progress / Me) comes online in W4.
//
// Current scope: prove the Bearer chain end-to-end through APIClient —
// show the signed-in user, hit /api/test_smoke/whoami with the typed
// client, and offer sign-out.

import SwiftUI

struct MainTabsView: View {
    let user: SessionUser
    @Environment(AuthService.self) private var auth

    @State private var pinging = false
    @State private var ping: Result<WhoamiResponse, Error>?

    var body: some View {
        VStack(spacing: 0) {
            hero
            Spacer()
            smokeSection
            Spacer()
            signOutBtn
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.tujiBg)
    }

    // MARK: - Bits

    private var hero: some View {
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
    }

    private var smokeSection: some View {
        VStack(spacing: Space.s4) {
            BBtn(
                title: pinging ? "驗證中..." : "Bearer smoke test",
                fullWidth: false,
                icon: "antenna.radiowaves.left.and.right",
                action: runPing
            )
            .frame(maxWidth: 280)
            .disabled(pinging)

            if let ping {
                resultCard(ping)
            }
        }
    }

    private var signOutBtn: some View {
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

    @ViewBuilder
    private func resultCard(_ result: Result<WhoamiResponse, Error>) -> some View {
        switch result {
        case .success(let r):
            VStack(alignment: .leading, spacing: Space.s2) {
                HStack(spacing: Space.s2) {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.tujiGreen)
                    Text("HTTP 200 · source: \(r.source.rawValue)")
                        .font(.tujiOverline)
                        .foregroundStyle(.tujiInk2)
                }
                if let uid = r.userId {
                    Text("userId: \(uid)").font(.tujiMono).foregroundStyle(.tujiInk2)
                } else {
                    Text("userId: nil (cookie/none path)").font(.tujiMono).foregroundStyle(.tujiInk3)
                }
            }
            .padding(Space.s4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.tujiCard, in: .rect(cornerRadius: Radius.lg))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.lg)
                    .stroke(.tujiInk4.opacity(0.25), lineWidth: 1)
            )
            .padding(.horizontal, Space.s6)

        case .failure(let e):
            VStack(alignment: .leading, spacing: Space.s2) {
                HStack(spacing: Space.s2) {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.tujiCoral)
                    Text("FAILED").font(.tujiOverline).foregroundStyle(.tujiCoral)
                }
                Text(e.localizedDescription)
                    .font(.tujiMono)
                    .foregroundStyle(.tujiInk2)
                    .multilineTextAlignment(.leading)
            }
            .padding(Space.s4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.tujiCoral.opacity(0.08), in: .rect(cornerRadius: Radius.lg))
            .padding(.horizontal, Space.s6)
        }
    }

    private var displayName: String {
        if let u = user.username, !u.isEmpty { return u }
        if let e = user.email, let local = e.split(separator: "@").first { return String(local) }
        return "Tuji 探險者"
    }

    private func runPing() {
        Task {
            pinging = true
            defer { pinging = false }
            do {
                let r: WhoamiResponse = try await APIClient.shared.get(.smokeWhoami)
                ping = .success(r)
            } catch {
                ping = .failure(error)
            }
        }
    }
}

#Preview {
    MainTabsView(user: SessionUser.preview)
        .environment(AuthService.shared)
}

extension SessionUser {
    fileprivate static var preview: SessionUser {
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
