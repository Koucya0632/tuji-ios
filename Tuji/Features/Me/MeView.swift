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
    @State private var showPaywall = false

    /// The rule this screen used to document — server entitlement first, device
    /// StoreKit flag only while it is unknown — now lives in
    /// `LiveEffectiveEntitlement`. 我的 and 設定 both read that same answer, so
    /// the account row cannot disagree with the paywall or quota UI.
    private let entitlement: any EffectiveEntitlementReading = LiveEffectiveEntitlement.shared

    private var isGuest: Bool {
        self.user == nil
    }

    /// 我 is no longer a directory of six entry points — it *is* your progress
    /// (D.8). The two menu cards are gone and their entries went where the thing
    /// they open actually lives: 圖鑑管理 to the 圖鑑 tab's 管理 → (only when the
    /// source filter is 我做的), 我的主頁 to the top of 物見, 我的收藏 to the
    /// 書籤 source filter, and 設定 to the gear in this screen's bar.
    ///
    /// The information order is: who you are (lightest) → what you have built up
    /// (the body) → where you are weakest (actionable) → settings (a corner).
    var body: some View {
        VStack(spacing: 0) {
            TujiNavBar(leading: .none) {
                NavigationLink(value: NavRoute.settings) {
                    Image(systemName: "gearshape")
                        .font(.tujiIcon(19, weight: .semibold))
                        .foregroundStyle(.tujiInk)
                        .frame(width: 44, height: 48)
                        .contentShape(.rect)
                }
                .accessibilityLabel(Text("設定"))
            }
            self.scroller
        }
        .background(.tujiPaper)
        // Metadata only (VoiceOver, back-button label on pushed screens,
        // multitasking window title) — the identity row is the visible title,
        // so the system nav bar itself stays hidden.
        .navigationTitle("我")
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: self.$showPaywall) { PaywallView() }
        .refreshable {
            if !self.isGuest {
                self.progress.invalidate()
                await self.vm.load(progress: self.progress)
            }
        }
        .task {
            if !self.isGuest {
                // Warm the 圖鑑管理 store from here (its parent screen) so tapping
                // into AtlasManageView renders from the cached singleton instead
                // of waiting on /api/atlas/sync. Fire-and-forget so it doesn't
                // block Me's own load; sync() is incremental after the first run.
                Task { await AtlasStore.shared.sync() }
                await self.vm.load(progress: self.progress)
            }
        }
    }

    private var scroller: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.s5) {
                self.identityRow
                MeProgressSections()
                self.weakSection
                    .padding(.horizontal, Space.s4)
                #if DEBUG
                // Dev-only Bearer smoke test. Compiled out of release /
                // App Store builds so end users never see it.
                DebugSmokeSection(isGuest: self.isGuest)
                    .padding(.horizontal, Space.s4)
                #endif
            }
            .padding(.bottom, Space.s6)
        }
    }

    // MARK: - Identity

    /// A row, not a hero. Who you are is the *lightest* thing on this screen —
    /// a 92pt centred avatar over your own name was the app telling you about
    /// yourself, which you already know. What you came for is below it.
    private var identityRow: some View {
        Button { self.showPaywall = true } label: {
            HStack(spacing: Space.s3) {
                ProfileAvatar(
                    avatar: self.isGuest ? nil : self.user?.avatar,
                    fallbackPose: .face,
                    size: 48
                )
                VStack(alignment: .leading, spacing: 2) {
                    Text(self.displayName)
                        .font(.tujiH3)
                        .foregroundStyle(.tujiInk)
                        .lineLimit(1)
                    if let handle = self.handle {
                        Text(verbatim: "\(tujiLocalized("UID")): \(handle)")
                            .font(.tujiMono)
                            .foregroundStyle(.tujiInk3)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
                HStack(spacing: Space.s2) {
                    TujiStatusEdgeLabel(
                        text: Text(verbatim: self.subscriptionTier),
                        edge: self.subscriptionEdge
                    )
                    Image(systemName: "arrow.right")
                        .font(.tujiIcon(16, weight: .semibold))
                        .foregroundStyle(.tujiInk3)
                }
                .fixedSize(horizontal: true, vertical: false)
            }
            .padding(.horizontal, Space.s4)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: "\(self.displayName), \(self.subscriptionTier)"))
    }

    // MARK: - Weak section

    @ViewBuilder
    private var weakSection: some View {
        if !self.isGuest, !self.vm.weakWords.isEmpty {
            self.wordSection(
                title: "需要加強",
                words: self.vm.weakWords,
                accent: .tujiAlert,
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
                .font(.tujiLabel)
                .tracking(2)
                .foregroundStyle(accent)
            VStack(spacing: 0) {
                ForEach(Array(words.enumerated()), id: \.element.id) { idx, word in
                    NavigationLink(value: NavRoute.wordDetail(id: word.id)) {
                        self.wordRow(word: word, accent: accent)
                    }
                    .buttonStyle(.plain)
                    // A NavigationLink has no tap callback, so the row's light
                    // haptic rides along on a simultaneous gesture.
                    .simultaneousGesture(TapGesture().onEnded {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    })
                    if idx < words.count - 1 {
                        Divider().background(.tujiRule.opacity(0.15))
                    }
                }
            }
            .background(.tujiPaper, in: .rect(cornerRadius: Radius.r0))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.r0)
                    .stroke(.tujiRule.opacity(0.2), lineWidth: 1)
            )
        }
    }

    private func wordRow(word: TopWord, accent: Color) -> some View {
        HStack(spacing: Space.s3) {
            ZStack {
                Rectangle().fill(.tujiAccumulationSoft)
                LazyImage(url: word.imageURL) { state in
                    if let image = state.image {
                        image.resizable().aspectRatio(contentMode: .fill)
                    } else {
                        Image(systemName: "photo").foregroundStyle(.tujiInk3)
                    }
                }
                .pipeline(.shared)
            }
            .frame(width: 44, height: 44)
            .clipShape(.rect(cornerRadius: Radius.r0))

            VStack(alignment: .leading, spacing: 2) {
                Text(word.word)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.tujiInk)
                if self.settings.current.showZh {
                    Text(word.chinese)
                        .font(.tujiLabel)
                        .foregroundStyle(.tujiInk3)
                        .lineLimit(1)
                }
            }
            Spacer()
            Text("\(word.mastery)")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(accent)
            Image(systemName: "chevron.right")
                .font(.tujiIcon(11, weight: .semibold))
                .foregroundStyle(.tujiInk3)
        }
        .padding(.horizontal, Space.s3)
        .padding(.vertical, Space.s3)
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

    private var subscriptionTier: String {
        self.entitlement.isPro ? "Pro" : "Free"
    }

    private var subscriptionEdge: Color {
        self.entitlement.isPro ? .tujiAccumulation : .tujiInk3
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
                        .font(.tujiLabel)
                        .tracking(2)
                        .foregroundStyle(.tujiInk3)
                    Spacer()
                    Image(systemName: self.open ? "chevron.up" : "chevron.down")
                        .font(.tujiIcon(11, weight: .semibold))
                        .foregroundStyle(.tujiInk3)
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
                        .font(.tujiLabel)
                        .foregroundStyle(.tujiInk3)
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
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.tujiAccumulation)
                    Text("HTTP 200 · source: \(r.source.rawValue)")
                        .font(.tujiLabel)
                        .foregroundStyle(.tujiInk2)
                }
                if let uid = r.userId {
                    Text("userId: \(uid)").font(.tujiMono).foregroundStyle(.tujiInk2)
                } else {
                    Text("userId: nil").font(.tujiMono).foregroundStyle(.tujiInk3)
                }
            }
            .padding(Space.s3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.tujiPaper, in: .rect(cornerRadius: Radius.r0))
        case let .failure(e):
            VStack(alignment: .leading, spacing: Space.s2) {
                HStack(spacing: Space.s2) {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.tujiAlert)
                    Text("FAILED").font(.tujiLabel).foregroundStyle(.tujiAlert)
                }
                Text(e.localizedDescription)
                    .font(.tujiMono)
                    .foregroundStyle(.tujiInk2)
            }
            .padding(Space.s3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.tujiAlert.opacity(0.08), in: .rect(cornerRadius: Radius.r0))
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
