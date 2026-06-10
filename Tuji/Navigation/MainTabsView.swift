// W2 placeholder for the post-login surface. Real 5-tab layout (Today /
// Cards / Tuji / Progress / Me) comes online in W4.
//
// Accepts an optional SessionUser — nil means the user is in guest mode
// (entered from Welcome's "先逛逛" link). Guest sees the favorites /
// learned counters from LocalCache and a "登入 / 註冊" button instead of
// "登出"; the smoke test button only works for signed-in users since it
// needs a Bearer token.

import SwiftUI

struct MainTabsView: View {
    let user: SessionUser?
    @Environment(AuthService.self) private var auth
    @Environment(LocalCache.self) private var cache

    @State private var pinging = false
    @State private var ping: Result<WhoamiResponse, Error>?

    private var isGuest: Bool {
        user == nil
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                hero
                Spacer()
                smokeSection
                browseButton
                Spacer()
                footerButton
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(.tujiBg)
            .navigationDestination(for: NavRoute.self) { route in
                switch route {
                case .cards: CardsListView()
                case let .wordDetail(id): WordDetailView(id: id)
                }
            }
        }
    }

    private var browseButton: some View {
        NavigationLink(value: NavRoute.cards) {
            HStack(spacing: Space.s2) {
                Image(systemName: "books.vertical.fill")
                Text("瀏覽圖鑑")
                Image(systemName: "chevron.right")
            }
            .font(.system(size: 15, weight: .heavy))
            .foregroundStyle(.tujiTeal)
            .padding(.vertical, Space.s3)
            .padding(.horizontal, Space.s6)
            .background(.tujiTealSoft, in: .capsule)
        }
        .padding(.top, Space.s4)
    }

    // MARK: - Bits

    private var hero: some View {
        VStack(spacing: Space.s4) {
            Mascot(pose: isGuest ? .think : .cheer, size: 88)

            VStack(spacing: Space.s1) {
                HStack(spacing: 0) {
                    Text(isGuest ? "嗨，" : "早安，")
                    Text(displayName).foregroundStyle(.tujiTeal)
                }
                .font(.tujiH2)
                .foregroundStyle(.tujiInk)

                if let user {
                    Text(user.email ?? "—")
                        .font(.tujiCaption)
                        .foregroundStyle(.tujiInk3)
                    Text("uid \(user.id.uuidString.prefix(8))")
                        .font(.tujiMono)
                        .foregroundStyle(.tujiInk4)
                } else {
                    Text("訪客模式 · 資料只存在這台裝置")
                        .font(.tujiCaption)
                        .foregroundStyle(.tujiInk3)
                    HStack(spacing: Space.s3) {
                        countChip(icon: "heart.fill", value: cache.favoriteIds.count, label: "收藏")
                        countChip(icon: "checkmark.seal.fill", value: cache.learnedIds.count, label: "已學")
                    }
                    .padding(.top, Space.s1)
                }
            }
        }
        .padding(.top, Space.s12)
    }

    private var smokeSection: some View {
        VStack(spacing: Space.s4) {
            BBtn(
                title: smokeButtonTitle,
                fullWidth: false,
                icon: "antenna.radiowaves.left.and.right",
                action: runPing
            )
            .frame(maxWidth: 280)
            .disabled(pinging || isGuest)

            if let ping {
                resultCard(ping)
            } else if isGuest {
                Text("登入後可驗證 Bearer 鏈")
                    .font(.tujiCaption)
                    .foregroundStyle(.tujiInk4)
            }
        }
    }

    private var footerButton: some View {
        Button {
            if isGuest {
                auth.exitGuestMode()
            } else {
                Task { await auth.signOut() }
            }
        } label: {
            Text(isGuest ? "登入 / 註冊" : "登出")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(isGuest ? .tujiTeal : .tujiCoral)
                .padding(.vertical, Space.s3)
                .padding(.horizontal, Space.s5)
                .background(
                    isGuest ? Color.tujiTealSoft : .tujiCoral.opacity(0.08),
                    in: .rect(cornerRadius: Radius.pill)
                )
        }
        .padding(.bottom, Space.s8)
    }

    @ViewBuilder
    private func resultCard(_ result: Result<WhoamiResponse, Error>) -> some View {
        switch result {
        case let .success(r):
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
                    Text("userId: nil").font(.tujiMono).foregroundStyle(.tujiInk3)
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

        case let .failure(e):
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

    private func countChip(icon: String, value: Int, label: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon).foregroundStyle(.tujiTeal)
            Text("\(value)")
                .font(.system(size: 14, weight: .heavy))
                .foregroundStyle(.tujiInk)
            Text(label)
                .font(.tujiCaption)
                .foregroundStyle(.tujiInk3)
        }
        .padding(.horizontal, Space.s3)
        .padding(.vertical, 6)
        .background(.tujiTealSoft, in: .rect(cornerRadius: Radius.pill))
    }

    private var displayName: String {
        if let user {
            if let u = user.username, !u.isEmpty { return u }
            if let e = user.email, let local = e.split(separator: "@").first { return String(local) }
        }
        return "Tuji 探險者"
    }

    private var smokeButtonTitle: String {
        if pinging { return "驗證中..." }
        if isGuest { return "需要登入" }
        return "Bearer smoke test"
    }

    private func runPing() {
        guard !isGuest else { return }
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

#Preview("Signed in") {
    MainTabsView(user: SessionUser.preview)
        .environment(AuthService.shared)
        .environment(LocalCache.shared)
}

#Preview("Guest") {
    MainTabsView(user: nil)
        .environment(AuthService.shared)
        .environment(LocalCache.shared)
}

private extension SessionUser {
    static var preview: SessionUser {
        SessionUser(
            id: UUID(),
            email: "preview@tuji.dev",
            username: "rex",
            avatar: nil
        )
    }

    init(id: UUID, email: String?, username: String?, avatar: String?) {
        self.id = id
        self.email = email
        self.username = username
        self.avatar = avatar
    }
}
