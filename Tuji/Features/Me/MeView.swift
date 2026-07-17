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

    private let progressRepository: ProgressRepository
    private let log = Logger(subsystem: "app.tuji.ios", category: "me")

    init(progressRepository: ProgressRepository = LiveProgressRepository.shared) {
        self.progressRepository = progressRepository
    }

    /// Streak + 已學字 (studied-word count) are read from ProgressStore.shared
    /// so Today / Progress / Me share a single fetched copy. Weak words live
    /// here because they're a Me-only payload.
    func load(progress: ProgressStore) async {
        self.loading = true
        defer { self.loading = false }
        // The weak-words fetch stays out of `async let`: that would send the
        // non-Sendable `any ProgressRepository` into a child task, which the
        // Swift 6 (TestFlight/WMO) build rejects. The two requests still
        // overlap — progressLoad runs in its child task while we await here.
        async let progressLoad: Void = progress.loadIfStale()
        let weak = try? await self.progressRepository.loadTopWords(type: "weak", limit: 3)
        await progressLoad
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
    @State private var store = StoreKitService.shared
    @State private var atlas = AtlasStore.shared
    @State private var peekId: String?
    @State private var showPaywall = false
    @State private var showFeedback = false
    @State private var showSignOutConfirm = false

    /// Prefer the server-authoritative Atlas entitlement (kept warm by the
    /// `.task` sync below) over the device-local StoreKit flag: `store.isPro`
    /// only reflects a transaction verified on this Apple ID/device via
    /// PaywallView, so it can read false for an account that's actually Pro
    /// (admin grant, cross-device purchase) until the paywall happens to open.
    private var isPro: Bool {
        self.atlas.entitlement?.isPro ?? self.store.isPro
    }

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

    /// Points at the public landing page until the App Store listing
    /// exists. Lives in code rather than a literal at the ShareLink call
    /// site so the no-hardcoded-base-url lint rule stays clean.
    private static let shareURL = URL(string: "https://tuji.nexflow.team/") ?? URL(fileURLWithPath: "/")

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
        // Metadata only (VoiceOver, back-button label on pushed screens,
        // multitasking window title) — `profileHeader` above is the visible
        // title, so the system nav bar itself stays hidden.
        .navigationTitle("我的")
        .toolbar(.hidden, for: .navigationBar)
        .refreshable {
            if !self.isGuest {
                self.progress.invalidate()
                await self.vm.load(progress: self.progress)
            }
        }
        .task {
            if !self.isGuest {
                // Warm the 自制圖鑑 store from here (its parent screen) so tapping
                // into AtlasManageView renders from the cached singleton instead
                // of waiting on /api/atlas/sync. Fire-and-forget so it doesn't
                // block Me's own load; sync() is incremental after the first run.
                Task { await AtlasStore.shared.sync() }
                await self.vm.load(progress: self.progress)
            }
        }
        .navigationDestination(item: self.$peekId) { id in
            WordDetailView(id: id)
        }
        .sheet(isPresented: self.$showPaywall) {
            PaywallView()
        }
        .sheet(isPresented: self.$showFeedback) {
            FeedbackSheet()
        }
        .tujiPrompt(
            isPresented: self.$showSignOutConfirm,
            style: .confirmation,
            title: "要登出 Tuji 嗎？",
            message: "收藏與設定會保留在伺服器。",
            primary: TujiPromptAction("登出") {
                Task { await self.auth.signOut() }
            },
            secondary: TujiPromptAction("取消", role: .cancel) {}
        )
    }

    // MARK: - Profile header

    private var profileHeader: some View {
        VStack(spacing: Space.s3) {
            MascotAvatar(pose: self.avatarPose, size: 92)
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

    private var avatarPose: MascotPose {
        if self.isGuest { return .think }
        return MascotPose(rawValue: self.user?.avatar ?? "") ?? .face
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
                iconTint: .tujiAmber
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

    private func statCell(
        value: String,
        label: LocalizedStringKey,
        icon: String? = nil,
        iconTint: Color = .clear
    )
        -> some View
    {
        VStack(spacing: 4) {
            HStack(spacing: 4) {
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 13, weight: .semibold))
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
        title: LocalizedStringKey,
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
                    .font(.system(size: 15, weight: .semibold))
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
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(accent)
            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.tujiInk4)
        }
        .padding(.horizontal, Space.s4)
        .padding(.vertical, Space.s3)
    }

    // MARK: - List group

    private var listGroup: some View {
        VStack(spacing: 0) {
            Button {
                self.showPaywall = true
            } label: {
                self.proEntry
            }
            .buttonStyle(.plain)
            Divider().background(.tujiInk4.opacity(0.15))
            NavigationLink(value: NavRoute.favorites) {
                self.listRow(icon: "heart.fill", title: "我的收藏", tint: .tujiCoral)
            }
            .buttonStyle(.plain)
            Divider().background(.tujiInk4.opacity(0.15))
            // 自制圖鑑 is account-scoped (uploads + cards live on the server),
            // so it's hidden for guests — they'd hit an empty, unusable page.
            if !self.isGuest {
                NavigationLink(value: NavRoute.atlasManage) {
                    self.listRow(icon: "camera.fill", title: "自制圖鑑", tint: .tujiTeal)
                }
                .buttonStyle(.plain)
                Divider().background(.tujiInk4.opacity(0.15))
            }
            NavigationLink(value: NavRoute.settings) {
                self.listRow(icon: "gearshape.fill", title: "設定", tint: .tujiInk3)
            }
            .buttonStyle(.plain)
            // 意見收集 is account-scoped; guests have no Bearer token so the
            // submit could only 401 — hidden, matching 自制圖鑑 above.
            if !self.isGuest {
                Divider().background(.tujiInk4.opacity(0.15))
                Button {
                    self.showFeedback = true
                } label: {
                    self.listRow(icon: "bubble.left.and.bubble.right.fill", title: "意見收集", tint: .tujiAmber)
                }
                .buttonStyle(.plain)
            }
            Divider().background(.tujiInk4.opacity(0.15))
            ShareLink(item: Self.shareURL) {
                self.listRow(icon: "square.and.arrow.up", title: "分享 App", tint: .tujiTeal)
            }
            // ShareLink has no tap callback — this records "share sheet
            // opened", not a completed share.
            .simultaneousGesture(TapGesture().onEnded {
                AnalyticsService.shared.track(.shareApp)
            })
        }
        .background(.tujiCard, in: .rect(cornerRadius: Radius.lg))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg)
                .stroke(.tujiInk4.opacity(0.2), lineWidth: 1)
        )
    }

    private var proEntry: some View {
        HStack(spacing: Space.s3) {
            ZStack {
                Circle()
                    .fill(.white.opacity(0.22))
                Image(systemName: "crown.fill")
                    .font(.system(size: 18, weight: .heavy))
                    .foregroundStyle(.tujiYellow)
            }
            .frame(width: 42, height: 42)

            VStack(alignment: .leading, spacing: 3) {
                Text("Tuji Pro")
                    .font(.system(size: 17, weight: .heavy))
                    .foregroundStyle(.white)
                Text("擴充自製圖鑑容量，解鎖高精度 AI 辨識")
                    .font(.tujiCaption)
                    .foregroundStyle(.white.opacity(0.82))
                    .lineLimit(2)
            }

            Spacer()

            Text(self.isPro ? LocalizedStringKey("已啟用") : LocalizedStringKey("升級"))
                .font(.system(size: 12, weight: .heavy))
                .foregroundStyle(.tujiInk)
                .padding(.horizontal, Space.s3)
                .padding(.vertical, 7)
                .background(.tujiYellow, in: .capsule)

            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .heavy))
                .foregroundStyle(.white.opacity(0.72))
        }
        .padding(.horizontal, Space.s4)
        .padding(.vertical, Space.s4)
        .frame(minHeight: 82)
        .background(
            LinearGradient(
                colors: [.tujiTeal, .tujiGreen],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .contentShape(Rectangle())
    }

    private func listRow(
        icon: String,
        title: LocalizedStringKey,
        tint: Color,
        subtitle: LocalizedStringKey? = nil
    )
        -> some View
    {
        HStack(spacing: Space.s3) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 0) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.tujiInk)
                if let subtitle {
                    Text(subtitle)
                        .font(.tujiCaption)
                        .foregroundStyle(.tujiInk4)
                }
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .semibold))
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
            Text(self.isGuest ? LocalizedStringKey("登入 / 註冊") : LocalizedStringKey("登出"))
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
        return tujiLocalized("Tuji 探險者")
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
                        .font(.system(size: 11, weight: .semibold))
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

    private var buttonTitle: LocalizedStringKey {
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
