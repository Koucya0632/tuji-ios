// Today (首頁) — design §III.E.
//
// Greeting → streak chip → hero card with stats + 2 CTAs → themes grid.
// What the screen needs loaded is named by `AccumulationLoading`, shared with
// 我 · 進度 and 主題. Guest mode skips the network and reads only LocalCache +
// WordsStore for a degraded hero.
//
// There used to be a `TodayVM` here. It held `me` / `loading` / `error` and no
// view read any of the three: it fetched GET /api/users/me on every appearance
// and every pull-to-refresh, wrote the response to a property nobody rendered,
// and threw it away. (That endpoint is not cheap — it is four queries including
// the account's whole learned set — and it has no side effect, so nothing was
// riding on the call either.) Its only real work was two `loadIfStale` calls,
// which arrived as *parameters* rather than as an injected seam, so no test
// could reach them. Both now live in the warm policy.
//
// One thing it did that nothing does now: it caught the load error. Nothing
// rendered `vm.error` either, so 首頁 already failed silently — giving the
// screen a real error surface is a separate decision, not a regression here.

import SwiftUI

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

    private var isGuest: Bool {
        user == nil
    }

    /// One snapshot of everything 首頁's decisions depend on, read from the
    /// environment here and answered in `TodayDecisions`. Reading the stores in
    /// this one place is also what registers the observation that re-renders
    /// the screen when any of them changes.
    private var decisions: TodayDecisions {
        let selected = self.settings.current.studyCategories
        let wanted = Set(selected)
        return TodayDecisions(
            .init(
                isGuest: self.isGuest,
                settingsLoaded: self.settings.hasLoaded,
                studyCategories: selected,
                dailyGoal: self.settings.current.dailyGoal,
                stats: self.studyStats.stats,
                guestLearnedCount: self.cache.learnedIds.count,
                progressLoaded: !self.progress.categoryProgress.isEmpty,
                seenInSelection: self.progress.seenCount(filter: selected),
                totalInSelection: self.progress.totalCount(filter: selected),
                dictionaryCount: self.words.words.count,
                dictionaryCountInSelection: self.words.words
                    .count(where: { wanted.contains($0.category) })
            )
        )
    }

    var body: some View {
        ScrollView {
            // No shared horizontal padding: the ink block bleeds to the screen
            // edges, so each section owns its own margin. A block with 24pt of
            // paper on either side is "a card"; one that reaches the edges is
            // "this part of the screen", and the difference in weight is large.
            VStack(alignment: .leading, spacing: Space.s5) {
                self.greeting.padding(.horizontal, Space.s4)
                self.hero
                self.themesSection
            }
            .padding(.top, Space.s3)
            .padding(.bottom, Space.s6)
        }
        .background(.tujiPaper)
        // Metadata only (VoiceOver, back-button label on pushed screens,
        // multitasking window title) — the greeting is the visible title, so
        // the system nav bar itself stays hidden.
        .navigationTitle("主頁")
        .toolbar(.hidden, for: .navigationBar)
        .refreshable {
            if !self.isGuest {
                self.progress.invalidate()
                self.studyStats.invalidate()
                self.mastery.invalidate()
                // Concurrent, unlike the warm path: the user is watching a
                // spinner here, and these are concrete `@MainActor` stores
                // rather than the existentials `AccumulationWarmer` holds, so
                // `async let` is available.
                async let progressReload: Void = self.progress.reload()
                async let statsReload: Void = self.studyStats.reload()
                async let masteryReload: Void = self.mastery.reload()
                await progressReload
                await statsReload
                await masteryReload
            }
            await self.words.reload()
            await self.categories.reload()
        }
        .warmsAccumulation(.todayHero, isGuest: self.isGuest) {
            guard !self.isGuest else { return }
            self.prefetchStudyQueues()
        }
    }

    /// Warm the study queue in the background (JSON only — card images stay
    /// lazy) so tapping 複習 / 學新字 skips the "載入練習中…" spinner. Only the
    /// enabled CTAs are prefetched, so a disabled button costs nothing, and the
    /// fetch replaces — not duplicates — the launcher's request for users who do
    /// study. Runs as the warm policy's `then`, so settings + stats (which drive
    /// the params) are already warm. StudyQueueStore's TTL + signature avoid
    /// re-fetching on tab swaps.
    private func prefetchStudyQueues() {
        if !self.reviewDisabled {
            Task { await StudyQueueStore.shared.prefetch(mode: .review) }
        }
        if !self.newDisabled {
            Task { await StudyQueueStore.shared.prefetch(mode: .new) }
        }
    }

    // MARK: - Top bar

    /// The row this used to sit in is gone. It held the word "Tuji" beside these
    /// two controls — the app's own name, told to someone already inside the app
    /// — and the row's height came from the search button rather than from the
    /// word, so deleting the word alone would have freed nothing. The controls
    /// moved onto the greeting's date line and the whole row went with it,
    /// worth about 56pt at the top of the tab.
    private var searchButton: some View {
        NavigationLink(value: NavRoute.search(query: nil)) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.tujiInk2)
                .padding(Space.s2)
                .background(.tujiPaper, in: .circle)
                .overlay(Circle().stroke(.tujiRule.opacity(0.3), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var streakChip: some View {
        let n = self.progress.streak?.current ?? 0
        HStack(spacing: 4) {
            Image(systemName: "flame.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(n > 0 ? .tujiAccumulation : .tujiInk3)
            Text("\(n)")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.tujiInk)
                .contentTransition(.numericText())
        }
        .padding(.horizontal, Space.s3)
        .padding(.vertical, 6)
        .background(.tujiPaper, in: .rect(cornerRadius: Radius.r0))
        .overlay(Rectangle().stroke(.tujiRule.opacity(0.3), lineWidth: 1))
        .tourAnchor(.streak)
    }

    // MARK: - Greeting

    private var greeting: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            // Search and the streak ride the date rather than the headline
            // below it: the headline is concatenated precisely so a long
            // localization wraps as one flowing line, and taking ~90pt off its
            // right edge would cost it an extra line — more than the row saved.
            HStack(spacing: Space.s3) {
                Text(self.dateLabel)
                    .font(.tujiLabel)
                    .tracking(2)
                    .foregroundStyle(.tujiInk3)
                Spacer(minLength: Space.s3)
                self.searchButton
                self.streakChip
            }
            // Concatenated so long localizations (en/ja) wrap as one flowing
            // line instead of an HStack pushing the name off to the side.
            (Text(self.greetingPrefix)
                + Text(self.displayName).foregroundStyle(.tujiInk)
                + Text("。"))
                .font(.tujiH2)
                .foregroundStyle(.tujiInk)
            Text(self.subtitle)
                .font(.tujiBodySm)
                .foregroundStyle(.tujiInk3)
        }
    }

    private var greetingPrefix: String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 5..<11: return tujiLocalized("早安，")
        case 11..<18: return tujiLocalized("午安，")
        default: return tujiLocalized("晚安，")
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

    /// Overline date in the interface language (reading `settings.current`
    /// here also registers the observation that re-renders the greeting
    /// block when the user switches languages).
    private var dateLabel: String {
        let f = DateFormatter()
        f.locale = self.settings.current.uiLanguage.locale
        f.setLocalizedDateFormatFromTemplate("EEEMMMd")
        return f.string(from: Date()).uppercased()
    }

    /// The words for `decisions.subtitle`. The verdict lives in
    /// `TodayDecisions`; this maps it to copy.
    private var subtitle: LocalizedStringKey {
        switch self.decisions.subtitle {
        case .guestBrowsing: "訪客模式 · 先逛逛圖鑑，想再看的字加書籤"
        case let .guestLearned(count): "訪客模式 · 已認得 \(count) 個字"
        case .pickThemes: "先選學習主題，開始學新字"
        case .unknown: "今天想學點什麼呢？"
        case let .reviewDue(count): "今天有 \(count) 個字要複習"
        case .goalReached: "今天目標達成，明天再來"
        case let .newDoneToday(count): "今天已學 \(count) 個新字，繼續加油"
        case .newAvailable: "今天還沒學新字，挑一個來試試"
        case .allLearnedInThemes: "這些主題的字都學過了，多選幾個主題吧"
        }
    }

    // MARK: - Hero card (deep ink)

    private var hero: some View {
        ZStack(alignment: .topTrailing) {
            VStack(alignment: .leading, spacing: Space.s3) {
                VStack(alignment: .leading, spacing: Space.s3) {
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
                    .buttonStyle(HeroPillStyle(role: .primary))

                    Text("免費註冊就能學新字、排複習，進度存在雲端")
                        .font(.tujiLabel)
                        .foregroundStyle(.tujiPaper.opacity(0.6))
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    HStack(spacing: Space.s3) {
                        NavigationLink(value: NavRoute.studyLanding(mode: .review)) {
                            Text("複習")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(HeroPillStyle(role: self.reviewDisabled ? .secondary : .primary))
                        .disabled(self.reviewDisabled)

                        NavigationLink(value: NavRoute.studyLanding(mode: .new)) {
                            Text("學新字")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(HeroPillStyle(role: self.reviewDisabled && !self
                                .newDisabled ? .primary : .secondary))
                        .disabled(self.newDisabled)
                    }
                    .tourAnchor(.heroCTAs)

                    if let hint = self.heroHint {
                        Text(hint)
                            .font(.tujiLabel)
                            .foregroundStyle(.tujiPaper.opacity(0.6))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .padding(Space.s4)
        .padding(.top, Space.s5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.tujiInk)
        // Applied over the background rather than inside it, so the cat can
        // straddle the top edge instead of sitting within the block. Its body is
        // ink, so the half that overlaps reads as a silhouette and only the
        // yellow eyes come forward — the gesture the logo already uses.
        .overlay(alignment: .topTrailing) {
            MascotFigure(
                pose: self.dailyGoalReached ? .cheer : .wave,
                size: 96,
                grounding: .none
            )
            .id(self.dailyGoalReached)
            .transition(.opacity)
            .offset(x: -Space.s4, y: -44)
        }
        .tourAnchor(.hero)
        .animation(
            // B.7 allows one curve. A spring here was the last bounce left in
            // the app.
            self.reduceMotion ? nil : Motion.ease(Motion.d3),
            value: self.dailyGoalReached
        )
    }

    private var dailyGoalReached: Bool {
        self.decisions.dailyGoalReached
    }

    /// Today's new-word goal progress. `todayNew` = new cards introduced today;
    /// dailyGoal is the per-day new-word target. Surfaces the goal on the home
    /// screen so there's a daily feedback loop. Signed-in only.
    @ViewBuilder
    private var dailyGoalProgress: some View {
        let done = self.studyStats.stats?.todayNew ?? 0
        let goal = max(1, self.settings.current.dailyGoal)
        // The verdict comes from the module, not from a second copy of the rule.
        // This line used to re-derive `done >= goal` here, without the guest
        // guard the module carries — and `TodayDecisions.subtitle` documents
        // that 達成 "wins over everything below so this line can never
        // contradict the 達成 badge on the hero card", while the badge was
        // being drawn from the copy.
        let reached = self.dailyGoalReached
        let ratio = CompletionReadout.ratio(seen: done, total: goal)
        VStack(alignment: .leading, spacing: Space.s1) {
            HStack {
                Text("今日目標")
                    .font(.tujiLabel)
                    .tracking(2)
                    .foregroundStyle(.tujiPaper.opacity(0.6))
                Spacer()
                if reached {
                    HStack(spacing: 3) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 11, weight: .semibold))
                        Text("達成")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .foregroundStyle(.tujiCurrent)
                } else {
                    Text("\(done) / \(goal)")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.tujiPaper.opacity(0.7))
                }
            }
            // Always 瞳黃. The unreached state used to be `tujiAlert`, which
            // said "you are failing" — not hitting today's goal at 10am is not
            // an error, it is the thing in progress, and 瞳黃 is exactly the
            // colour for that.
            TujiProgressBar(progress: ratio, track: .tujiPaper.opacity(0.2), fill: .tujiCurrent)
        }
        .tourAnchor(.dailyGoal)
    }

    @ViewBuilder
    private var heroProgress: some View {
        let readout = self.decisions.completion
        let learned = readout.seen
        let total = readout.total
        VStack(alignment: .leading, spacing: Space.s1) {
            HStack {
                Text("主題進度")
                    .font(.tujiLabel)
                    .tracking(2)
                    .foregroundStyle(.tujiPaper.opacity(0.6))
                Spacer()
                Text("\(learned) / \(total)")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.tujiPaper.opacity(0.7))
            }
            // Deep teal only reaches 3.04:1 against ink; the pale step reaches
            // 13.58:1 and carries the same "accumulation" meaning. On ink
            // surfaces it is always the pale one.
            TujiProgressBar(
                progress: readout.ratio,
                track: .tujiPaper.opacity(0.2),
                fill: .tujiAccumulationSoft
            )
        }
    }

    private var reviewDisabled: Bool {
        self.decisions.reviewDisabled
    }

    private var newDisabled: Bool {
        self.decisions.newDisabled
    }

    /// Caption shown under the hero CTAs explaining why 學新字 is greyed.
    private var newBlockHint: LocalizedStringKey? {
        switch self.decisions.newBlock {
        case .allLearned: "這些主題的新字都學完了，去複習或多選幾個主題"
        case .noCards: "這個主題目前還沒有可學的字"
        case .reviewBacklog: "要複習的字有點多，先清一些再學新字"
        case .noThemes, .none: nil
        }
    }

    private var newQuotaAdjustmentHint: LocalizedStringKey? {
        guard let adj = self.decisions.quotaAdjustment else { return nil }
        // tujiLocalized resolves the interpolated key against the uiLang; wrap
        // the already-localized result verbatim (a String-keyed
        // LocalizedStringKey never re-looks-up, which is why the old
        // LocalizedStringKey(rawChinese) leaked Chinese into ja/en UIs).
        return LocalizedStringKey(
            tujiLocalized("因為還有 \(adj.due) 個字要複習，今天新字先調整為 \(adj.limit) 個。")
        )
    }

    /// One explanatory line under the CTAs. A greyed 學新字 explains itself
    /// (newBlockHint); otherwise a greyed 複習 gets its own line so neither
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
                            .font(.tujiLabel)
                            .tracking(0.5)
                            .foregroundStyle(.tujiInk3)
                        Spacer()
                        // Named for where it goes. The strip shows the themes
                        // *you picked*, so the action beside it is changing
                        // that pick — but it used to be labelled "全部 →",
                        // which promises the whole catalogue and delivers a
                        // settings multi-select. Browsing every theme is 主題's
                        // job, on 圖鑑.
                        NavigationLink(value: NavRoute.studyCategories) {
                            Text("學習主題 →")
                                .font(.tujiLabel)
                                .tracking(0.5)
                                .foregroundStyle(.tujiInk)
                                .underline()
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, Space.s4)

                    // Horizontal, not a 3-up grid. Three tiles filled the row and
                    // the screen simply stopped; scrolling says "there is more"
                    // and hands the vertical space back to the ink block.
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: Space.s2) {
                            ForEach(tiles, id: \.id) { c in
                                NavigationLink(value: NavRoute.categoryDetail(id: c.id)) {
                                    CategoryTile(
                                        category: c,
                                        wordCount: self.words.byCategory(c.id).count,
                                        status: self.themeStatus(for: c.id)
                                    )
                                    .frame(width: 160)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, Space.s4)
                    }
                }
            }
        }
    }

    /// Signed-in user has loaded settings but picked no study themes — nudge
    /// them to choose so the grid + new-word flow have something to show.
    private var showThemePrompt: Bool {
        self.decisions.showThemePrompt
    }

    private var themePrompt: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            Text("主題")
                .font(.tujiLabel)
                .tracking(0.5)
                .foregroundStyle(.tujiInk3)
            VStack(alignment: .leading, spacing: Space.s3) {
                Text("還沒選學習主題")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.tujiInk)
                Text("選幾個你想學的主題，這裡會顯示它們，學新字也會從中出題。")
                    .font(.tujiLabel)
                    .foregroundStyle(.tujiInk3)
                NavigationLink(value: NavRoute.studyCategories) {
                    Text("選擇主題")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.tujiInk)
                        .padding(.vertical, Space.s3)
                        .padding(.horizontal, Space.s4)
                        .background(.tujiCurrent, in: .rect(cornerRadius: Radius.r0))
                }
                .buttonStyle(.plain)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Space.s4)
            .background(.tujiPaper, in: .rect(cornerRadius: Radius.r0))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.r0)
                    .stroke(.tujiRule, lineWidth: 1)
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

    /// Completion state for a theme tile. The rule itself lives on ThemeStatus
    /// so 主題 (CategoryIndexView) asks the same question the same way.
    private func themeStatus(for id: String) -> ThemeStatus {
        ThemeStatus.of(
            words: self.words.byCategory(id),
            masteryScore: { self.mastery.score(for: $0) },
            progress: self.progress.categoryProgress,
            categoryId: id
        )
    }
}

// MARK: - Subviews

/// The two buttons on the ink block. Only one of them is primary at a time, and
/// which one depends on what the user can actually do right now.
///
/// 複習 is disabled whenever nothing is due. Hard-coding it as the primary meant
/// that on a day with no reviews the screen showed a *disabled* primary button
/// beside an enabled secondary one — the only available action drawn as the
/// lesser of the two.
private enum HeroPillRole {
    case primary
    case secondary
}

private struct HeroPillStyle: ButtonStyle {
    let role: HeroPillRole
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.tujiH3)
            .foregroundStyle(self.foreground)
            .padding(.vertical, Space.s3)
            .padding(.horizontal, Space.s3)
            .background(self.background(pressed: configuration.isPressed))
    }

    private var foreground: Color {
        guard self.isEnabled else { return .tujiPaper.opacity(0.4) }
        return .tujiInk
    }

    /// Enabled buttons get a *light* ground, disabled ones a translucent wash.
    ///
    /// The secondary used to be a 20%-paper fill on ink — a dark grey block on a
    /// near-black block, which is what "switched off" looks like everywhere else
    /// in the app. It sat two opacity steps from the genuinely disabled state and
    /// read as the same thing, so 學新字 looked untappable on every day that had
    /// reviews due, which is most days.
    ///
    /// Two grounds that are both clearly lit, then, with the hierarchy carried by
    /// hue rather than by brightness: 瞳 means 現在 and marks the recommended
    /// action, paper is the same "available but not selected" ground the 圖鑑
    /// chips use. An outline was the other option and the system forbids it —
    /// a resting element with a border is a bug (see Border.swift).
    private func background(pressed: Bool) -> Color {
        guard self.isEnabled else { return .tujiPaper.opacity(0.08) }
        switch self.role {
        // Press changes the ground and nothing moves, the same rule BBtn
        // follows. `tujiPaper3` rather than `tujiPaper2` so the step is as
        // visible as 瞳's — paper2 → paper3 differ by too little to feel.
        case .primary: return pressed ? .tujiCurrentDeep : .tujiCurrent
        case .secondary: return pressed ? .tujiPaper3 : .tujiPaper2
        }
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
