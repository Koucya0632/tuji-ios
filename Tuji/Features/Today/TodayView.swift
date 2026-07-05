// Today (首頁) — design §III.E.
//
// Greeting → streak chip → hero card with stats + 2 CTAs → themes grid.
// Owns a private TodayVM that concurrently fetches /users/me +
// /study/stats + /users/progress (async let). Guest mode skips the
// network and reads only LocalCache + WordsStore for a degraded hero.

import OSLog
import Observation
import SwiftUI

@MainActor
@Observable
final class TodayVM {
    var me: UserMeResponse?
    var loading = true
    var error: Error?

    private let users: UserRepository
    private let log = Logger(subsystem: "app.tuji.ios", category: "today")

    init(users: UserRepository = LiveUserRepository.shared) {
        self.users = users
    }

    /// Streak + study stats come from shared stores (ProgressStore,
    /// StudyStatsStore) so Today, Progress, Me, StudyLanding, and
    /// CompleteView don't each round-trip on tab swap.
    func load(progress: ProgressStore, studyStats: StudyStatsStore) async {
        self.loading = true
        self.error = nil
        defer { self.loading = false }
        async let progressLoad: Void = progress.loadIfStale()
        async let statsLoad: Void = studyStats.loadIfStale()
        do {
            let me = try await self.users.loadMe()
            await progressLoad
            await statsLoad
            self.me = me
            self.log.info(
                "today loaded streak=\(progress.streak?.current ?? 0, privacy: .public) due=\(studyStats.stats?.due ?? 0, privacy: .public)"
            )
        } catch {
            self.error = error
            self.log.error("today load failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}

struct TodayView: View {
    let user: SessionUser?

    @Environment(WordsStore.self) private var words
    @Environment(CategoriesStore.self) private var categories
    @Environment(LocalCache.self) private var cache
    @Environment(ProgressStore.self) private var progress
    @Environment(StudyStatsStore.self) private var studyStats
    @Environment(SettingsStore.self) private var settings
    @Environment(MasteryStore.self) private var mastery
    @Environment(AuthService.self) private var auth
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var vm = TodayVM()

    private var isGuest: Bool {
        user == nil
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.s5) {
                self.topBar
                self.greeting
                self.hero
                self.themesSection
            }
            .padding(.horizontal, Space.s6)
            .padding(.top, Space.s4)
            .padding(.bottom, Space.s12)
        }
        .background(.tujiBg)
        .refreshable {
            if !self.isGuest {
                self.progress.invalidate()
                self.studyStats.invalidate()
                self.mastery.invalidate()
                await self.vm.load(progress: self.progress, studyStats: self.studyStats)
                await self.mastery.reload()
            }
            await self.words.reload()
            await self.categories.reload()
        }
        .task {
            await self.words.loadIfNeeded()
            await self.categories.loadIfNeeded()
            await self.settings.loadIfNeeded()
            if !self.isGuest {
                await self.vm.load(progress: self.progress, studyStats: self.studyStats)
                // Powers the 完成 / 全精通 badges on the theme tiles.
                await self.mastery.loadIfNeeded()
                self.prefetchStudyQueues()
            }
        }
    }

    /// Warm the study queue in the background (JSON only — card images stay
    /// lazy) so tapping 復習 / 學新字 skips the "載入練習中…" spinner. Only the
    /// enabled CTAs are prefetched, so a disabled button costs nothing, and the
    /// fetch replaces — not duplicates — the launcher's request for users who do
    /// study. Runs after vm.load so settings + stats (which drive the params)
    /// are warm. StudyQueueStore's TTL + signature avoid re-fetching on tab swaps.
    private func prefetchStudyQueues() {
        if !self.reviewDisabled {
            Task { await StudyQueueStore.shared.prefetch(mode: .review) }
        }
        if !self.newDisabled {
            Task { await StudyQueueStore.shared.prefetch(mode: .new) }
        }
    }

    // MARK: - Top bar

    private var topBar: some View {
        HStack(spacing: Space.s3) {
            Text("Tuji")
                .font(.tujiH2)
                .foregroundStyle(.tujiInk)
            Spacer()
            NavigationLink(value: NavRoute.search) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.tujiInk2)
                    .padding(Space.s2)
                    .background(.tujiCard, in: .circle)
                    .overlay(Circle().stroke(.tujiInk4.opacity(0.3), lineWidth: 1))
            }
            .buttonStyle(.plain)
            self.streakChip
        }
    }

    @ViewBuilder
    private var streakChip: some View {
        let n = self.progress.streak?.current ?? 0
        HStack(spacing: 4) {
            Image(systemName: "flame.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(n > 0 ? .tujiAmber : .tujiInk4)
            Text("\(n)")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.tujiInk)
                .contentTransition(.numericText())
        }
        .padding(.horizontal, Space.s3)
        .padding(.vertical, 6)
        .background(.tujiCard, in: .capsule)
        .overlay(Capsule().stroke(.tujiInk4.opacity(0.3), lineWidth: 1))
    }

    // MARK: - Greeting

    private var greeting: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Text(self.dateLabel)
                .font(.tujiOverline)
                .tracking(2)
                .foregroundStyle(.tujiInk3)
            HStack(spacing: 0) {
                Text(self.greetingPrefix)
                Text(self.displayName).foregroundStyle(.tujiTeal)
                Text("。")
            }
            .font(.tujiH2)
            .foregroundStyle(.tujiInk)
            Text(self.subtitle)
                .font(.tujiBody)
                .foregroundStyle(.tujiInk3)
        }
    }

    private var greetingPrefix: String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 5..<11: return "早安，"
        case 11..<18: return "午安，"
        default: return "晚安，"
        }
    }

    private var displayName: String {
        if let user {
            if let n = user.nickname, !n.isEmpty { return n }
            if let u = user.username, !u.isEmpty { return u }
            if let e = user.email, let local = e.split(separator: "@").first { return String(local) }
        }
        return tujiLocalized("探險者")
    }

    private var dateLabel: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "EEE · MMM d"
        return f.string(from: Date()).uppercased()
    }

    private var subtitle: LocalizedStringKey {
        if self.isGuest {
            let learned = self.cache.learnedIds.count
            return learned > 0
                ? "訪客模式 · 已認得 \(learned) 個字"
                : "訪客模式 · 先逛逛圖鑑，喜歡的字按愛心收藏"
        }
        if self.showThemePrompt {
            return "先選學習主題，開始學新字"
        }
        // Until the day's stats have loaded there's nothing truthful to say —
        // a neutral line beats a wrong verdict ("都學過了" flashing on a brand
        // new account while the first fetch is in flight).
        guard let stats = self.studyStats.stats else {
            return "今天想學點什麼呢？"
        }
        if stats.due > 0 {
            return "今天有 \(stats.due) 個字要復習"
        }
        // Goal reached wins over everything below so this line can never
        // contradict the 達成 badge on the hero card.
        if self.dailyGoalReached {
            return "今天目標達成，明天再來"
        }
        if let done = stats.todayNew, done > 0 {
            return "今天已學 \(done) 個新字，繼續加油"
        }
        if self.newAvailable > 0 {
            return "今天還沒學新字，挑一個來試試"
        }
        return "這些主題的字都學過了，多選幾個主題吧"
    }

    // MARK: - Hero card (deep ink)

    private var hero: some View {
        ZStack(alignment: .topTrailing) {
            VStack(alignment: .leading, spacing: Space.s4) {
                VStack(alignment: .leading, spacing: Space.s4) {
                    if !self.isGuest {
                        self.dailyGoalProgress
                    }
                    self.heroProgress
                }
                .padding(.trailing, 96)

                if self.isGuest {
                    // Guests can't study (SRS is account-scoped), so instead of
                    // two permanently-dead buttons the hero offers the one
                    // action that actually works: creating an account.
                    Button {
                        self.auth.exitGuestMode()
                    } label: {
                        Text("建立帳號，開始學習")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(HeroPillStyle(fg: .white, bg: .tujiTeal))

                    Text("免費註冊就能學新字、排復習，進度存在雲端")
                        .font(.tujiCaption)
                        .foregroundStyle(.white.opacity(0.6))
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    HStack(spacing: Space.s3) {
                        NavigationLink(value: NavRoute.studyLanding(mode: .review)) {
                            Text("復習")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(HeroPillStyle(fg: .tujiInk, bg: .tujiYellow))
                        .disabled(self.reviewDisabled)

                        NavigationLink(value: NavRoute.studyLanding(mode: .new)) {
                            Text("學新字")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(HeroPillStyle(fg: .white, bg: .tujiTeal))
                        .disabled(self.newDisabled)
                    }

                    if let hint = self.heroHint {
                        Text(hint)
                            .font(.tujiCaption)
                            .foregroundStyle(.white.opacity(0.6))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            MascotFigure(
                pose: self.dailyGoalReached ? .cheer : .wave,
                size: 104,
                grounding: .glow
            )
            .id(self.dailyGoalReached)
            .transition(.scale(scale: 0.92).combined(with: .opacity))
            .offset(x: 12, y: -22)
        }
        .padding(Space.s5)
        .padding(.top, Space.s2)
        .background(.tujiBgInk, in: .rect(cornerRadius: Radius.xl))
        .animation(
            self.reduceMotion ? nil : .spring(duration: 0.32, bounce: 0.18),
            value: self.dailyGoalReached
        )
    }

    private var dailyGoalReached: Bool {
        guard !self.isGuest else { return false }
        let goal = max(1, self.settings.current.dailyGoal)
        return (self.studyStats.stats?.todayNew ?? 0) >= goal
    }

    /// Today's new-word goal progress. `todayNew` = new cards introduced today;
    /// dailyGoal is the per-day new-word target. Surfaces the goal on the home
    /// screen so there's a daily feedback loop. Signed-in only.
    @ViewBuilder
    private var dailyGoalProgress: some View {
        let done = self.studyStats.stats?.todayNew ?? 0
        let goal = max(1, self.settings.current.dailyGoal)
        let reached = done >= goal
        let ratio = min(1.0, Double(done) / Double(goal))
        VStack(alignment: .leading, spacing: Space.s1) {
            HStack {
                Text("今日目標")
                    .font(.tujiOverline)
                    .tracking(2)
                    .foregroundStyle(.white.opacity(0.6))
                Spacer()
                if reached {
                    HStack(spacing: 3) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 11, weight: .semibold))
                        Text("達成")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .foregroundStyle(.tujiYellow)
                } else {
                    Text("\(done) / \(goal)")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.7))
                }
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(.white.opacity(0.08))
                    RoundedRectangle(cornerRadius: 4)
                        .fill(reached ? Color.tujiYellow : .tujiCoral)
                        .frame(width: geo.size.width * ratio)
                }
            }
            .frame(height: 8)
        }
    }

    @ViewBuilder
    private var heroProgress: some View {
        let learned = self.dexSeen
        let total = self.dexTotal
        let ratio = total > 0 ? min(1.0, Double(learned) / Double(total)) : 0
        VStack(alignment: .leading, spacing: Space.s1) {
            HStack {
                Text("主題進度")
                    .font(.tujiOverline)
                    .tracking(2)
                    .foregroundStyle(.white.opacity(0.6))
                Spacer()
                Text("\(learned) / \(total)")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.7))
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(.white.opacity(0.08))
                    RoundedRectangle(cornerRadius: 4)
                        .fill(.tujiTeal)
                        .frame(width: geo.size.width * ratio)
                }
            }
            .frame(height: 8)
        }
    }

    /// Words studied at least once (server "seen"), matching the Progress
    /// tab's completion source. Guests have no SRS state, so fall back to
    /// the local learned set. With no themes selected, the progress reads 0/0
    /// to match the "pick themes first" empty state.
    private var dexSeen: Int {
        if self.isGuest { return self.cache.learnedIds.count }
        if self.showThemePrompt { return 0 }
        return self.progress.seenCount(filter: self.settings.current.studyCategories)
    }

    /// Total published words in the selected categories. Server count when
    /// available, else the locally known dictionary size.
    private var dexTotal: Int {
        if self.showThemePrompt { return 0 }
        let serverTotal = self.progress.totalCount(filter: self.settings.current.studyCategories)
        return serverTotal > 0 ? serverTotal : self.words.words.count
    }

    private var reviewDisabled: Bool {
        self.isGuest || (self.studyStats.stats?.due ?? 0) == 0
    }

    /// New words still to learn within the selected themes. New cards = those
    /// with no SRS row yet, i.e. (total − seen) scoped to studyCategories —
    /// derived from ProgressStore so it tracks the selection without a stats
    /// refetch. Falls back to the global `new` count before progress loads.
    private var newAvailable: Int {
        let cats = self.settings.current.studyCategories
        if self.progress.categoryProgress.isEmpty {
            return self.studyStats.stats?.new ?? 0
        }
        return max(0, self.progress.totalCount(filter: cats) - self.progress.seenCount(filter: cats))
    }

    /// Why 學新字 is unavailable, so the hero can explain the dead-end instead
    /// of leaving a silently greyed button. The common one is `.allLearned`:
    /// an early/small theme (e.g. 廚房 — seeded first, so its cards carry the
    /// lowest ids and get drawn first) empties before the rest.
    private enum NewBlockReason {
        case none
        case noThemes
        case noCards
        case allLearned
        case reviewBacklog
    }

    private var newBlockReason: NewBlockReason {
        // Guests can't study new words; the prompt to sign in lives elsewhere.
        if self.isGuest { return .none }
        // No themes selected → nothing to draw new words from; the user must
        // pick themes first (review stays available — it spans all studied words).
        if self.settings.current.studyCategories.isEmpty { return .noThemes }
        let cats = self.settings.current.studyCategories
        // total == 0 with progress loaded means the selected themes have no
        // cards in the current deck — e.g. a theme with no 日文 cards yet —
        // which is a different dead-end from "you've learned them all".
        if !self.progress.categoryProgress.isEmpty,
           self.progress.totalCount(filter: cats) == 0
        {
            return .noCards
        }
        if self.newAvailable == 0 { return .allLearned }
        // When the review backlog crowds out the new-card quota
        // (computeNewLimit hits 0 once due > 100), grey out the button
        // instead of letting the user enter the launcher only to bounce
        // back on an empty queue.
        let due = self.studyStats.stats?.due ?? 0
        let goal = self.settings.current.dailyGoal
        if StudyQuotas.computeNewLimit(goal: goal, due: due) == 0 {
            return .reviewBacklog
        }
        return .none
    }

    private var newDisabled: Bool {
        self.isGuest || self.newBlockReason != .none
    }

    /// Caption shown under the hero CTAs explaining why 學新字 is greyed.
    private var newBlockHint: LocalizedStringKey? {
        switch self.newBlockReason {
        case .allLearned: "這些主題的新字都學完了，去複習或多選幾個主題"
        case .noCards: "這個主題目前還沒有可學的字"
        case .reviewBacklog: "要複習的字有點多，先清一些再學新字"
        case .noThemes, .none: nil
        }
    }

    private var newQuotaAdjustmentHint: LocalizedStringKey? {
        guard let text = Self.newQuotaAdjustmentHintText(
            isGuest: self.isGuest,
            stats: self.studyStats.stats,
            newAvailable: self.newAvailable,
            dailyGoal: self.settings.current.dailyGoal
        ) else { return nil }
        return LocalizedStringKey(text)
    }

    static func newQuotaAdjustmentHintText(
        isGuest: Bool,
        stats: StudyStats?,
        newAvailable: Int,
        dailyGoal: Int
    ) -> String? {
        guard !isGuest, let stats else { return nil }
        let goal = max(1, dailyGoal)
        guard (stats.todayNew ?? 0) < goal else { return nil }
        guard newAvailable > 0 else { return nil }
        let limit = StudyQuotas.computeNewLimit(goal: goal, due: stats.due)
        guard limit > 0, limit < goal else { return nil }
        return "因為還有 \(stats.due) 個字要複習，今天新字先調整為 \(limit) 個。"
    }

    /// One explanatory line under the CTAs. A greyed 學新字 explains itself
    /// (newBlockHint); otherwise a greyed 復習 gets its own line so neither
    /// button is ever silently dead. Waits for stats so it never claims
    /// "nothing due" before the first fetch answers.
    private var heroHint: LocalizedStringKey? {
        if let hint = self.newBlockHint { return hint }
        if let hint = self.newQuotaAdjustmentHint { return hint }
        if self.reviewDisabled, self.studyStats.stats != nil {
            return "今天沒有要複習的字，先學點新的吧"
        }
        return nil
    }

    // MARK: - Themes grid

    @ViewBuilder
    private var themesSection: some View {
        if self.showThemePrompt {
            self.themePrompt
        } else {
            let tiles = self.themeTiles
            if !tiles.isEmpty {
                VStack(alignment: .leading, spacing: Space.s3) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("主題")
                            .font(.tujiOverline)
                            .tracking(2)
                            .foregroundStyle(.tujiTeal)
                        Spacer()
                        NavigationLink(value: NavRoute.cards) {
                            Text("全部 →")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(.tujiInk3)
                        }
                        .buttonStyle(.plain)
                    }
                    LazyVGrid(
                        columns: Array(
                            repeating: GridItem(.flexible(), spacing: Space.s2),
                            count: 3
                        ),
                        spacing: Space.s2
                    ) {
                        ForEach(tiles, id: \.id) { c in
                            NavigationLink(value: NavRoute.categoryDetail(id: c.id)) {
                                CategoryTile(
                                    category: c,
                                    wordCount: self.words.byCategory(c.id).count,
                                    status: self.themeStatus(for: c.id)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }

    /// Signed-in user has loaded settings but picked no study themes — nudge
    /// them to choose so the grid + new-word flow have something to show.
    private var showThemePrompt: Bool {
        !self.isGuest
            && self.settings.hasLoaded
            && self.settings.current.studyCategories.isEmpty
    }

    private var themePrompt: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            Text("主題")
                .font(.tujiOverline)
                .tracking(2)
                .foregroundStyle(.tujiTeal)
            VStack(alignment: .leading, spacing: Space.s3) {
                Text("還沒選學習主題")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.tujiInk)
                Text("選幾個你想學的主題，這裡會顯示它們，學新字也會從中出題。")
                    .font(.tujiCaption)
                    .foregroundStyle(.tujiInk3)
                NavigationLink(value: NavRoute.studyCategories) {
                    Text("選擇主題")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.vertical, Space.s3)
                        .padding(.horizontal, Space.s5)
                        .background(.tujiTeal, in: .capsule)
                }
                .buttonStyle(.plain)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Space.s5)
            .background(.tujiCard, in: .rect(cornerRadius: Radius.lg))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.lg)
                    .stroke(.tujiInk4.opacity(0.2), lineWidth: 1)
            )
        }
    }

    /// Guests get a discovery preview (first 4 categories that have words).
    /// Signed-in users see exactly their selected themes (that have words).
    private var themeTiles: [TujiCategory] {
        let presentIds = Set(self.words.categories)
        let known = self.categories.categories.filter { presentIds.contains($0.id) }
        if self.isGuest {
            return Array(known.prefix(4))
        }
        let selected = Set(self.settings.current.studyCategories)
        guard !selected.isEmpty else { return [] }
        return known.filter { selected.contains($0.id) }
    }

    /// Completion state for a theme tile. `.mastered` (全精通) wins over
    /// `.completed` (完成) since all-精通 already implies every word was seen.
    /// Guests have no mastery / progress data, so this stays `.none`.
    private func themeStatus(for id: String) -> ThemeStatus {
        let wordsInCat = self.words.byCategory(id)
        guard !wordsInCat.isEmpty else { return .none }
        // 全精通: every word in the theme sits at the top tier (精通, score ≥ 80).
        // An unstudied word reads as 未學, so all-精通 also means all-seen.
        let allMastered = wordsInCat.allSatisfy {
            MasteryLevel.from(score: self.mastery.score(for: $0.id)) == .expert
        }
        if allMastered { return .mastered }
        // 完成: the server says every published card in the theme has been
        // studied at least once (seen == total), even if some later decayed
        // below 精通.
        if let row = self.progress.categoryProgress.first(where: { $0.category == id }),
           row.total > 0, row.seen == row.total
        {
            return .completed
        }
        return .none
    }
}

/// Theme-tile completion marker shown on the Today grid.
enum ThemeStatus {
    case none
    case completed
    case mastered
}

// MARK: - Subviews

private struct CategoryTile: View {
    let category: TujiCategory
    let wordCount: Int
    var status: ThemeStatus = .none

    private var accent: Color {
        switch self.status {
        case .mastered: .tujiPurple
        case .completed: .tujiTeal
        case .none: .tujiInk4.opacity(0.2)
        }
    }

    var body: some View {
        VStack(spacing: 3) {
            Text(self.category.nameZh)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.tujiInk)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            Text("\(self.wordCount) 字")
                .font(.tujiCaption)
                .foregroundStyle(.tujiInk3)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, Space.s2)
        .padding(.vertical, Space.s3)
        .background(.tujiCard, in: .rect(cornerRadius: Radius.lg))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg)
                .stroke(self.accent, lineWidth: self.status == .none ? 1 : 1.5)
        )
        .overlay(alignment: .topTrailing) {
            ThemeStatusBadge(status: self.status)
                .padding(5)
        }
    }
}

/// Corner marker on a Today theme tile: 完成 once every word has been seen,
/// 全精通 once every word reaches 精通. Renders nothing for `.none`.
private struct ThemeStatusBadge: View {
    let status: ThemeStatus

    var body: some View {
        switch self.status {
        case .none:
            EmptyView()
        case .completed:
            self.pill(text: "完成", icon: "checkmark.seal.fill", tint: .tujiTeal)
        case .mastered:
            self.pill(text: "全精通", icon: "crown.fill", tint: .tujiPurple)
        }
    }

    private func pill(text: String, icon: String, tint: Color) -> some View {
        HStack(spacing: 2) {
            Image(systemName: icon)
                .font(.system(size: 8, weight: .semibold))
            Text(text)
                .font(.system(size: 9, weight: .semibold))
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 5)
        .padding(.vertical, 2)
        .background(.tujiCard, in: .capsule)
        .overlay(Capsule().stroke(tint.opacity(0.4), lineWidth: 1))
        .shadow(color: .black.opacity(0.1), radius: 1.5, y: 1)
    }
}

private struct HeroPillStyle: ButtonStyle {
    let fg: Color
    let bg: Color
    @Environment(\.isEnabled) private var isEnabled

    /// Disabled = ghost (faint fill + hairline + dim label). Dropping the
    /// whole pill to 0.4 opacity turned the yellow 復習 into a muddy olive
    /// blob on the deep-ink hero card.
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15, weight: .heavy))
            .foregroundStyle(self.isEnabled ? self.fg : .white.opacity(0.4))
            .padding(.vertical, Space.s3)
            .padding(.horizontal, Space.s4)
            .background(
                self.isEnabled ? self.bg : Color.white.opacity(0.06),
                in: .rect(cornerRadius: Radius.md)
            )
            .overlay {
                if !self.isEnabled {
                    RoundedRectangle(cornerRadius: Radius.md)
                        .stroke(.white.opacity(0.2), lineWidth: 1.5)
                }
            }
            .opacity(configuration.isPressed && self.isEnabled ? 0.85 : 1)
    }
}

#Preview("Signed in") {
    NavigationStack {
        TodayView(user: SessionUser.todayPreview)
            .environment(WordsStore.shared)
            .environment(CategoriesStore.shared)
            .environment(LocalCache.shared)
            .environment(ProgressStore.shared)
            .environment(StudyStatsStore.shared)
            .environment(SettingsStore.shared)
            .environment(MasteryStore.shared)
            .environment(AuthService.shared)
    }
}

#Preview("Guest") {
    NavigationStack {
        TodayView(user: nil)
            .environment(WordsStore.shared)
            .environment(CategoriesStore.shared)
            .environment(LocalCache.shared)
            .environment(ProgressStore.shared)
            .environment(StudyStatsStore.shared)
            .environment(SettingsStore.shared)
            .environment(MasteryStore.shared)
            .environment(AuthService.shared)
    }
}

private extension SessionUser {
    static var todayPreview: SessionUser {
        SessionUser(id: UUID(), email: "preview@tuji.dev", username: "rex", avatar: nil)
    }

    init(id: UUID, email: String?, username: String?, avatar: String?) {
        self.id = id
        self.email = email
        self.username = username
        self.nickname = nil
        self.avatar = avatar
    }
}
