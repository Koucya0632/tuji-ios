// Me tab — full §III.M lands later. For now it consolidates account
// status, counters, the Bearer smoke test (dev-only verification of
// the auth chain), and sign-out / sign-in entry.

import SwiftUI

struct MeView: View {
    let user: SessionUser?
    @Environment(AuthService.self) private var auth
    @Environment(LocalCache.self) private var cache

    @State private var pinging = false
    @State private var ping: Result<WhoamiResponse, Error>?

    private var isGuest: Bool {
        self.user == nil
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.s5) {
                self.header
                self.counters
                self.smokeSection
                self.actions
            }
            .padding(.horizontal, Space.s6)
            .padding(.top, Space.s4)
            .padding(.bottom, Space.s24)
        }
        .background(.tujiBg)
    }

    // MARK: - Bits

    private var header: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Text("我的")
                .font(.tujiH2)
                .foregroundStyle(.tujiInk)
            HStack(spacing: Space.s3) {
                Mascot(pose: self.isGuest ? .think : .cheer, size: 56)
                VStack(alignment: .leading, spacing: 2) {
                    Text(self.displayName)
                        .font(.tujiH3)
                        .foregroundStyle(.tujiInk)
                    if let user {
                        Text(user.email ?? "—")
                            .font(.tujiCaption)
                            .foregroundStyle(.tujiInk3)
                        Text("uid \(user.id.uuidString.prefix(8))")
                            .font(.tujiMono)
                            .foregroundStyle(.tujiInk4)
                    } else {
                        Text("訪客模式")
                            .font(.tujiCaption)
                            .foregroundStyle(.tujiInk3)
                        Text("資料只存在這台裝置")
                            .font(.tujiCaption)
                            .foregroundStyle(.tujiInk4)
                    }
                }
            }
            .padding(Space.s4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.tujiTealSoft, in: .rect(cornerRadius: Radius.lg))
        }
    }

    private var counters: some View {
        HStack(spacing: Space.s3) {
            NavigationLink(value: NavRoute.favorites) {
                self.counter(
                    icon: "heart.fill",
                    value: self.cache.favoriteIds.count,
                    label: "收藏",
                    tint: .tujiCoral,
                    showChevron: true
                )
            }
            .buttonStyle(.plain)
            self.counter(
                icon: "checkmark.seal.fill",
                value: self.cache.learnedIds.count,
                label: "已學",
                tint: .tujiTeal,
                showChevron: false
            )
        }
    }

    private func counter(icon: String, value: Int, label: String, tint: Color, showChevron: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: icon).foregroundStyle(tint)
                Text(label)
                    .font(.tujiOverline)
                    .tracking(2)
                    .foregroundStyle(.tujiInk3)
                Spacer()
                if showChevron {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .heavy))
                        .foregroundStyle(.tujiInk4)
                }
            }
            Text("\(value)")
                .font(.system(size: 28, weight: .heavy))
                .foregroundStyle(.tujiInk)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Space.s4)
        .background(.tujiCard, in: .rect(cornerRadius: Radius.lg))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg)
                .stroke(.tujiInk4.opacity(0.2), lineWidth: 1)
        )
    }

    private var smokeSection: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            Text("除錯工具")
                .font(.tujiOverline)
                .tracking(2)
                .foregroundStyle(.tujiInk3)
            BBtn(
                title: self.smokeButtonTitle,
                fullWidth: true,
                icon: "antenna.radiowaves.left.and.right",
                action: self.runPing
            )
            .disabled(self.pinging || self.isGuest)
            if let ping {
                self.resultCard(ping)
            } else if self.isGuest {
                Text("登入後可驗證 Bearer 鏈")
                    .font(.tujiCaption)
                    .foregroundStyle(.tujiInk4)
            }
        }
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
        }
    }

    private var actions: some View {
        Button {
            if self.isGuest {
                self.auth.exitGuestMode()
            } else {
                Task { await self.auth.signOut() }
            }
        } label: {
            Text(self.isGuest ? "登入 / 註冊" : "登出")
                .font(.system(size: 15, weight: .heavy))
                .foregroundStyle(self.isGuest ? .tujiTeal : .tujiCoral)
                .frame(maxWidth: .infinity)
                .padding(.vertical, Space.s4)
                .background(
                    self.isGuest ? Color.tujiTealSoft : .tujiCoral.opacity(0.08),
                    in: .rect(cornerRadius: Radius.lg)
                )
        }
        .buttonStyle(.plain)
    }

    private var displayName: String {
        if let user {
            if let u = user.username, !u.isEmpty { return u }
            if let e = user.email, let local = e.split(separator: "@").first { return String(local) }
        }
        return "Tuji 探險者"
    }

    private var smokeButtonTitle: String {
        if self.pinging { return "驗證中…" }
        if self.isGuest { return "需要登入" }
        return "Bearer smoke test"
    }

    private func runPing() {
        guard !self.isGuest else { return }
        Task {
            self.pinging = true
            defer { self.pinging = false }
            do {
                let r: WhoamiResponse = try await APIClient.shared.get(.smokeWhoami)
                self.ping = .success(r)
            } catch {
                self.ping = .failure(error)
            }
        }
    }
}
