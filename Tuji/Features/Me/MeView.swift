// Me tab — full §III.M surface. Profile header, 3-stat row, top-3 weak
// word rows (tap → WordPeek), and a list group for Favorites / Settings /
// Share. Sign-out and the dev-only Bearer smoke test live under a 除錯工具
// disclosure at the bottom.

import Nuke
import NukeUI
import Observation
import OSLog
import SwiftUI

@MainActor
@Observable
final class MeVM {
    var weakWords: [TopWord] = []
    var loading: Bool = false

    private let log = Logger(subsystem: "app.tuji.ios", category: "me")

    /// Streak + 已學字 (studied-word count) are read from ProgressStore.shared
    /// so Today / Progress / Me share a single fetched copy. Weak words live
    /// here because they're a Me-only payload.
    func load(progress: ProgressStore) async {
        self.loading = true
        defer { self.loading = false }
        async let weakResp: TopWordsResponse? = try? APIClient.shared.get(
            .usersTopWords(type: "weak", limit: 3)
        )
        async let progressLoad: Void = progress.loadIfStale()
        let (weak, _) = await (weakResp, progressLoad)
        self.weakWords = weak?.words ?? []
    }
}

struct MeView: View {
    let user: SessionUser?
    @Environment(AuthService.self) private var auth
    @Environment(LocalCache.self) private var cache
    @Environment(ProgressStore.self) private var progress
    @Environment(SettingsStore.self) private var settings

    @State private var vm = MeVM()
    @State private var peekId: String?
    @State private var showSignOutConfirm = false

    private var isGuest: Bool {
        self.user == nil
    }

    /// 已學字 = distinct words the account has studied at least once. The real
    /// value is server-derived: it's the sum of per-category `seen` counts from
    /// /api/users/progress (one user_cards row per studied word). Guests have no
    /// server record, so they fall back to the on-device learned set.
    private var learnedCount: Int {
        if self.isGuest { return self.cache.learnedIds.count }
        return self.progress.categoryProgress.reduce(0) { $0 + $1.seen }
    }

    /// Placeholder share URL until the App Store listing exists. Lives
    /// in code rather than a literal at the ShareLink call site so the
    /// no-hardcoded-base-url lint rule stays clean.
    private static let shareURL = URL(string: "https://apps.apple.com/app/tuji") ?? URL(fileURLWithPath: "/")

    var body: some View {
        ScrollView {
            VStack(spacing: Space.s6) {
                self.profileHeader
                self.statsRow
                self.weakSection
                self.listGroup
                #if DEBUG
                // Dev-only Bearer smoke test. Compiled out of release /
                // App Store builds so end users never see it.
                DebugSmokeSection(isGuest: self.isGuest)
                #endif
                self.signOutButton
            }
            .padding(.horizontal, Space.s6)
            .padding(.top, Space.s4)
            .padding(.bottom, Space.s24)
        }
        .background(.tujiBg)
        .refreshable {
            if !self.isGuest {
                self.progress.invalidate()
                await self.vm.load(progress: self.progress)
            }
        }
        .task {
            if !self.isGuest { await self.vm.load(progress: self.progress) }
        }
        .navigationDestination(item: self.$peekId) { id in
            WordDetailView(id: id)
        }
        .alert("登出？", isPresented: self.$showSignOutConfirm) {
            Button("取消", role: .cancel) {}
            Button("登出", role: .destructive) {
                Task { await self.auth.signOut() }
            }
        } message: {
            Text("收藏與設定會保留在伺服器")
        }
    }

    // MARK: - Profile header

    private var profileHeader: some View {
        VStack(spacing: Space.s3) {
            ZStack {
                Circle().fill(.tujiTealSoft)
                Mascot(pose: self.isGuest ? .think : .face, size: 56)
            }
            .frame(width: 88, height: 88)
            Text(self.displayName)
                .font(.tujiH3)
                .foregroundStyle(.tujiInk)
            if let handle = self.handle {
                Text("@\(handle)")
                    .font(.tujiMono)
                    .foregroundStyle(.tujiInk3)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, Space.s5)
    }

    // MARK: - Stats row

    private var statsRow: some View {
        HStack(spacing: 0) {
            self.statCell(value: "\(self.learnedCount)", label: "已學字")
            Divider().frame(height: 36)
            self.statCell(
                value: "\(self.progress.streak?.current ?? 0)",
                label: "連勝天",
                icon: "flame.fill",
                iconTint: .tujiCoral
            )
            Divider().frame(height: 36)
            self.statCell(value: "\(self.cache.favoriteIds.count)", label: "收藏")
        }
        .padding(.vertical, Space.s3)
        .background(.tujiCard, in: .rect(cornerRadius: Radius.lg))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg)
                .stroke(.tujiInk4.opacity(0.2), lineWidth: 1)
        )
    }

    private func statCell(value: String, label: String, icon: String? = nil, iconTint: Color = .clear) -> some View {
        VStack(spacing: 4) {
            HStack(spacing: 4) {
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 13, weight: .heavy))
                        .foregroundStyle(iconTint)
                }
                Text(value)
                    .font(.system(size: 22, weight: .heavy))
                    .foregroundStyle(.tujiInk)
                    .contentTransition(.numericText())
            }
            Text(label)
                .font(.tujiCaption)
                .foregroundStyle(.tujiInk3)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Weak section

    @ViewBuilder
    private var weakSection: some View {
        if !self.isGuest, !self.vm.weakWords.isEmpty {
            self.wordSection(
                title: "需要加強",
                words: self.vm.weakWords,
                accent: .tujiCoral,
                emptyText: nil
            )
        }
    }

    private func wordSection(
        title: String,
        words: [TopWord],
        accent: Color,
        emptyText _: String?
    )
        -> some View
    {
        VStack(alignment: .leading, spacing: Space.s3) {
            Text(title)
                .font(.tujiOverline)
                .tracking(2)
                .foregroundStyle(accent)
            VStack(spacing: 0) {
                ForEach(Array(words.enumerated()), id: \.element.id) { idx, word in
                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        self.peekId = word.id
                    } label: {
                        self.wordRow(word: word, accent: accent)
                    }
                    .buttonStyle(.plain)
                    if idx < words.count - 1 {
                        Divider().background(.tujiInk4.opacity(0.15))
                    }
                }
            }
            .background(.tujiCard, in: .rect(cornerRadius: Radius.lg))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.lg)
                    .stroke(.tujiInk4.opacity(0.2), lineWidth: 1)
            )
        }
    }

    private func wordRow(word: TopWord, accent: Color) -> some View {
        HStack(spacing: Space.s3) {
            ZStack {
                Rectangle().fill(.tujiTealSoft)
                LazyImage(url: word.imageURL) { state in
                    if let image = state.image {
                        image.resizable().aspectRatio(contentMode: .fill)
                    } else {
                        Image(systemName: "photo").foregroundStyle(.tujiInk4)
                    }
                }
                .pipeline(.shared)
            }
            .frame(width: 44, height: 44)
            .clipShape(.rect(cornerRadius: Radius.md))

            VStack(alignment: .leading, spacing: 2) {
                Text(word.word)
                    .font(.system(size: 15, weight: .heavy))
                    .foregroundStyle(.tujiInk)
                if self.settings.current.showZh {
                    Text(word.chinese)
                        .font(.tujiCaption)
                        .foregroundStyle(.tujiInk3)
                        .lineLimit(1)
                }
            }
            Spacer()
            Text("\(word.mastery)")
                .font(.system(size: 14, weight: .heavy))
                .foregroundStyle(accent)
            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .heavy))
                .foregroundStyle(.tujiInk4)
        }
        .padding(.horizontal, Space.s4)
        .padding(.vertical, Space.s3)
    }

    // MARK: - List group

    private var listGroup: some View {
        VStack(spacing: 0) {
            NavigationLink(value: NavRoute.favorites) {
                self.listRow(icon: "heart.fill", title: "我的收藏", tint: .tujiCoral)
            }
            .buttonStyle(.plain)
            Divider().background(.tujiInk4.opacity(0.15))
            NavigationLink(value: NavRoute.settings) {
                self.listRow(icon: "gearshape.fill", title: "設定", tint: .tujiInk3)
            }
            .buttonStyle(.plain)
            Divider().background(.tujiInk4.opacity(0.15))
            ShareLink(item: Self.shareURL) {
                self.listRow(icon: "square.and.arrow.up", title: "分享 App", tint: .tujiTeal)
            }
        }
        .background(.tujiCard, in: .rect(cornerRadius: Radius.lg))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg)
                .stroke(.tujiInk4.opacity(0.2), lineWidth: 1)
        )
    }

    private func listRow(icon: String, title: String, tint: Color, subtitle: String? = nil) -> some View {
        HStack(spacing: Space.s3) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .heavy))
                .foregroundStyle(tint)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 0) {
                Text(title)
                    .font(.system(size: 15, weight: .heavy))
                    .foregroundStyle(.tujiInk)
                if let subtitle {
                    Text(subtitle)
                        .font(.tujiCaption)
                        .foregroundStyle(.tujiInk4)
                }
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .heavy))
                .foregroundStyle(.tujiInk4)
        }
        .padding(.horizontal, Space.s4)
        .padding(.vertical, Space.s4)
        .frame(minHeight: 52)
        // Make the whole row (incl. the Spacer gap) tappable, not just the
        // text/icon glyphs.
        .contentShape(Rectangle())
    }

    private var signOutButton: some View {
        Button {
            if self.isGuest {
                self.auth.exitGuestMode()
            } else {
                self.showSignOutConfirm = true
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

    // MARK: - Helpers

    private var displayName: String {
        if let user {
            if let n = user.nickname, !n.isEmpty { return n }
            if let u = user.username, !u.isEmpty { return u }
            if let e = user.email, let local = e.split(separator: "@").first { return String(local) }
        }
        return "Tuji 探險者"
    }

    private var handle: String? {
        if self.isGuest { return "guest" }
        if let u = user?.username, !u.isEmpty { return u }
        if let e = user?.email, let local = e.split(separator: "@").first {
            return String(local)
        }
        return nil
    }
}

// MARK: - Debug / smoke (collapsible, DEBUG builds only)

#if DEBUG
private struct DebugSmokeSection: View {
    let isGuest: Bool
    @State private var open = false
    @State private var pinging = false
    @State private var ping: Result<WhoamiResponse, Error>?

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Button {
                withAnimation(.spring(duration: 0.25)) { self.open.toggle() }
            } label: {
                HStack {
                    Text("除錯工具")
                        .font(.tujiOverline)
                        .tracking(2)
                        .foregroundStyle(.tujiInk3)
                    Spacer()
                    Image(systemName: self.open ? "chevron.up" : "chevron.down")
                        .font(.system(size: 11, weight: .heavy))
                        .foregroundStyle(.tujiInk4)
                }
            }
            .buttonStyle(.plain)
            if self.open {
                BBtn(
                    title: self.buttonTitle,
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
        case let .failure(e):
            VStack(alignment: .leading, spacing: Space.s2) {
                HStack(spacing: Space.s2) {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.tujiCoral)
                    Text("FAILED").font(.tujiOverline).foregroundStyle(.tujiCoral)
                }
                Text(e.localizedDescription)
                    .font(.tujiMono)
                    .foregroundStyle(.tujiInk2)
            }
            .padding(Space.s4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.tujiCoral.opacity(0.08), in: .rect(cornerRadius: Radius.lg))
        }
    }

    private var buttonTitle: String {
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
#endif
