// Today (首頁).
//
// 問候 → 墨塊 → Moira 和她的四個入口 → 主題格子。
//
// 墨塊收過一次。它本來是「兩條進度（今日目標、主題進度）+ 兩顆並排按鈕
// （複習、學新字）+ 一行解釋某顆按鈕為什麼反灰的提示」，現在是「主題標題 +
// 一條總進度 + 一顆按鈕 + 最多一行」。三件事跟著變：
//
//   1. 兩顆按鈕併成一顆。模式由 `TodayDecisions.call` 挑 —— 有欠複習就複習，
//      否則學新字。代價寫在那裡：有字要複習的人不能再自己選今天只學新字，
//      按鈕底下那行 `.switchToNew` 是唯一的退路。
//   2. 今日目標那條刪掉，主題進度那條改成總字數。首頁因此沒有每日回饋迴圈了
//      —— 這是知情的取捨，不是遺漏。連帶「達成」徽章也沒了，它本來就長在
//      今日目標那條上。
//   3. 提示行變成 `TodayDecisions.footer`，永遠最多一行，說的永遠是「你還能
//      做的另一件事」，而不是「這顆按鈕為什麼不能按」。
//
// 墨塊上另外有三顆圖示，三顆都不印字：標題右邊的 ⚙ 換學習主題，右上角的折線圖
// 開 學習統計（我 頁上的那幾塊數字），右下角的 ⓘ 開 記憶曲線。
//
// 「和 Moira 一起」是併進來的 `AssistantHomeView`：一隻會呼吸的貓加四個入口。
// 原本那一頁的招呼和靜態揮手貓都沒搬，見 `AssistantFeatures.swift`。
//
// 螢幕量測沿用：整頁算成一屏高，主題格子吃剩下的高度。墨塊和 Moira 區變高之後
// 剩的高度通常是負的，格子就退回兩排的下限、頁面開始捲 —— 這正是設計要的樣子。

import SwiftUI

struct TodayView: View {
    @Environment(WordsStore.self) private var words
    @Environment(CategoriesStore.self) private var categories
    @Environment(ProgressStore.self) private var progress
    @Environment(StudyStatsStore.self) private var studyStats
    @Environment(SettingsStore.self) private var settings
    @Environment(MasteryStore.self) private var mastery
    @Environment(AuthService.self) private var auth
    @Environment(TabNavigator.self) private var navigator
    @Environment(\.presentPaywall) private var presentPaywall

    /// 打卡. Owned by `MainTabsView`, not by the sheet, so the chip's dot, the
    /// sheet and the 學新字 finish screen read one wallet.
    @Environment(CheckInModel.self) private var checkIn
    @State private var showingCheckIn = false
    @State private var showingReviewCurve = false

    /// One snapshot of everything 首頁's decisions depend on, read from the
    /// environment here and answered in `TodayDecisions`. Reading the stores in
    /// this one place is also what registers the observation that re-renders
    /// the screen when any of them changes.
    private var decisions: TodayDecisions {
        TodayDecisions(
            .init(
                completion: .init(
                    settings: self.settings,
                    progress: self.progress,
                    words: self.words
                ),
                dailyGoal: self.settings.current.dailyGoal,
                stats: self.studyStats.stats,
                progressLoaded: self.progress.phase == .loaded,
                freeThemes: FreeThemesProgress(
                    studyable: self.settings.studyableCategories,
                    progress: self.progress
                )
            )
        )
    }

    var body: some View {
        GeometryReader { screen in
            ScrollView {
                // No shared horizontal padding: the ink block bleeds to the screen
                // edges, so each section owns its own margin. A block with 24pt of
                // paper on either side is "a card"; one that reaches the edges is
                // "this part of the screen", and the difference in weight is large.
                VStack(alignment: .leading, spacing: Space.s4) {
                    self.greeting.padding(.horizontal, Space.s4)
                    self.hero
                    self.moiraSection
                    self.themesGrid
                }
                .padding(.top, Space.s3)
                .padding(.bottom, Space.s4)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { total in
                    // The tab bar's inset comes off the screen: content is free
                    // to scroll under the bar, but the strip is not free to end
                    // under it.
                    let page = screen.size.height - screen.safeAreaInsets.bottom
                    self.themeStripSpace = page - (total - self.themeStripHeight)
                }
            }
            // A new screen size (rotation, Stage Manager) invalidates the
            // measurement, and the content's own height may not change with it,
            // so nothing above would fire. Dropping back to the floor makes the
            // strip re-measure from scratch.
            .onChange(of: screen.size.height) { self.themeStripSpace = nil }
            .background(.tujiPaper)
            // Metadata only (VoiceOver, back-button label on pushed screens,
            // multitasking window title) — the greeting is the visible title, so
            // the system nav bar itself stays hidden.
            .navigationTitle("主頁")
            .toolbar(.hidden, for: .navigationBar)
            .refreshable {
                // What a pull re-reads is `LearningRefresh`'s to say. This list was
                // written here, and 我 and 清除學習進度 each wrote their own.
                await LiveLearningRefresher().refresh(after: .pulledToday)
            }
            .warmsAccumulation(.todayHero) {
                self.prefetchStudyQueue()
                self.prefetchAssistantOffers()
            }
            .task { await self.checkIn.loadRewardIfStale() }
            // A new answer today re-reads the wallet regardless of age: the
            // first one is what makes the points claimable.
            .onChange(of: self.progress.streak?.todayCount) { old, new in
                guard let old, let new, new > old else { return }
                Task { await self.checkIn.loadReward() }
            }
            .tujiSheet(isPresented: self.$showingCheckIn, title: "打卡", height: 640) {
                CheckInSheet(
                    model: self.checkIn,
                    fallbackStreak: self.progress.streak,
                    onStudy: self.studyFromCheckIn
                )
            }
            .tujiSheet(isPresented: self.$showingReviewCurve, title: "記憶曲線", height: 540) {
                ReviewCurveSheet()
            }
        }
    }

    /// Warm the study queue in the background (JSON only — card images stay
    /// lazy) so tapping 背單字 skips the "載入練習中…" spinner.
    ///
    /// One mode, not two. It used to prefetch whichever of 複習／學新字 was
    /// enabled, which on a normal day meant two fetches for two buttons; there
    /// is one button now and `call` already knows which queue it will ask for.
    private func prefetchStudyQueue() {
        guard case let .study(mode, _) = self.decisions.call else { return }
        Task { await StudyQueueStore.shared.prefetch(mode: mode) }
    }

    /// 情境故事 / AI 查詞 / AI 語法 的報價，預熱。
    ///
    /// 本來掛在助手首頁的 `.task`。那一頁沒了，入口搬到這裡，預熱就跟著搬。
    private func prefetchAssistantOffers() {
        Task { await AssistantHomeFeature.prefetchOffers() }
    }

    // MARK: - Top bar

    private var searchButton: some View {
        NavigationLink(value: NavRoute.search(query: nil)) {
            Image(systemName: "magnifyingglass")
                .font(.tujiIcon(16, weight: .semibold))
                .foregroundStyle(.tujiInk2)
                .padding(Space.s2)
                .background(.tujiPaper, in: .circle)
                .overlay(Circle().stroke(.tujiRule.opacity(0.3), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    /// The chip opens 打卡. Its dot means exactly one thing — points a tap would
    /// collect — so it is never decoration and never a nag to study.
    private var streakChip: some View {
        Button { self.showingCheckIn = true } label: {
            self.streakChipLabel
        }
        .buttonStyle(.plain)
        .overlay(alignment: .topTrailing) {
            if self.checkInBadge {
                Circle()
                    .fill(.tujiAlert)
                    .frame(width: 8, height: 8)
                    .offset(x: 3, y: -3)
                    .accessibilityHidden(true)
            }
        }
        .accessibilityLabel(Text("打卡"))
        .accessibilityValue(Text("連續 \(self.progress.streak?.current ?? 0) 天"))
        .accessibilityHint(self.checkInBadge ? Text("有點數可以領取") : Text(verbatim: ""))
    }

    private var checkInBadge: Bool {
        CheckInDecision.chipBadge(
            self.checkIn.reward(fallbackStudiedToday: (self.progress.streak?.todayCount ?? 0) > 0)
        )
    }

    /// 去學習 from inside the sheet: close it and take the hero's own advice.
    /// One button now, so there is one answer — the same `call` the hero reads,
    /// rather than this screen's own second copy of the review-first rule.
    private func studyFromCheckIn() {
        self.showingCheckIn = false
        switch self.decisions.call {
        case let .study(mode, _): self.navigator.push(.studyLanding(mode: mode))
        case .pickThemes: self.navigator.push(.studyCategories)
        case .unknown: self.navigator.push(.studyLanding(mode: .review))
        case .blocked: break
        }
    }

    @ViewBuilder
    private var streakChipLabel: some View {
        let n = self.progress.streak?.current ?? 0
        HStack(spacing: 4) {
            Image(systemName: "flame.fill")
                .font(.tujiIcon(12, weight: .semibold))
                .foregroundStyle(n > 0 ? .tujiAccumulation : .tujiInk3)
            Text("\(n)")
                .font(.tujiBodySm(.strong))
                .foregroundStyle(.tujiInk)
                .contentTransition(.numericText())
        }
        .padding(.horizontal, Space.s3)
        .padding(.vertical, 6)
        .background(.tujiPaper, in: .rect(cornerRadius: Radius.r0))
        .overlay(Rectangle().stroke(.tujiRule.opacity(0.3), lineWidth: 1))
    }

    // MARK: - Greeting

    /// 日期列 + 一句招呼。
    ///
    /// 招呼底下那行副標沒了。它是 `TodayDecisions.subtitle` 的七個 case —— 其中
    /// 四個在講今日目標或今天學了幾個，而今日目標那條已經不在畫面上；剩下的
    /// 搬進了墨塊自己的標題、按鈕和那一行。
    private var greeting: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack(spacing: Space.s3) {
                Text(self.dateLabel)
                    .font(.tujiLabel)
                    .tracking(2)
                    // 墨3 在紙上只有 3.6:1，而這是 13pt 的字。同一句話在墨2 上
                    // 是 9.2:1，看起來幾乎一樣。
                    .foregroundStyle(.tujiInk2)
                Spacer(minLength: Space.s3)
                self.searchButton
                // 罐頭跟火焰站一起：兩個都是「你的計數器」。
                AssistantCreditLink()
                self.streakChip
            }
            // Concatenated so long localizations (en/ja) wrap as one flowing
            // line instead of an HStack pushing the name off to the side.
            (Text(self.greetingPrefix)
                + Text(self.displayName).foregroundStyle(.tujiInk)
                + Text("。"))
                .font(.tujiH2)
                .foregroundStyle(.tujiInk)
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

    /// The fallback is this screen's copy — 今天 greets 「探險者」 where 我 titles
    /// the row 「Tuji 探險者」 — so it stays here while the derivation does not.
    private var displayName: String {
        self.auth.displayName(fallback: tujiLocalized("探險者"))
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

    // MARK: - 墨塊

    private var hero: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            self.heroHeading
            self.heroProgress
            VStack(spacing: Space.s2) {
                self.studyButton
                self.heroFootRow
            }
        }
        .padding(Space.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.tujiInk)
        .tourAnchor(.hero)
    }

    /// 標題列：你在學哪些主題，加上改主題和看統計。
    ///
    /// 右邊那個折線圖一度是 記憶曲線 的入口。那是一張「為什麼今天先複習」的
    /// 解釋圖，不是你的數字 —— 而一個折線圖的圖示擺在首頁右上角，點下去誰都
    /// 以為會看到自己的數字。所以圖示留在原位、改開 我 的那幾塊統計；曲線換成
    /// 一個問號性質的圖示，搬到墨塊右下角（見 `reviewCurveButton`）。
    private var heroHeading: some View {
        HStack(spacing: 0) {
            Text(self.headingText)
                .font(.tujiH3)
                .foregroundStyle(.tujiPaper)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            NavigationLink(value: NavRoute.studyCategories) {
                Image(systemName: "slider.horizontal.3")
                    .font(.tujiIcon(15, weight: .semibold))
                    .foregroundStyle(.tujiPaper.opacity(0.75))
                    .frame(width: 32, height: 32)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("更換學習主題"))
            Spacer(minLength: Space.s2)
            NavigationLink(value: NavRoute.progressStats) {
                Image(systemName: "chart.line.uptrend.xyaxis")
                    .font(.tujiIcon(16, weight: .semibold))
                    .foregroundStyle(.tujiPaper.opacity(0.85))
                    .frame(width: 32, height: 32)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("學習統計"))
        }
    }

    /// 「便利商店 等 6 個主題」。一個主題就只報它的名字，查不到名字就只報數量。
    private var headingText: LocalizedStringKey {
        switch self.decisions.heading {
        // settings 還沒到。說「還沒選學習主題」會是一句很快就被打臉的話，
        // 所以先報一個不宣稱任何事的名詞。
        case .unknown:
            return "學習主題"
        case .noThemes:
            return "還沒選學習主題"
        case let .themes(firstId, count):
            guard let name = self.categories.categories.first(where: { $0.id == firstId })?.nameZh else {
                return LocalizedStringKey(tujiLocalized("\(count) 個學習主題"))
            }
            guard count > 1 else { return LocalizedStringKey(name) }
            return LocalizedStringKey(tujiLocalized("\(name) 等 \(count) 個主題"))
        }
    }

    /// 總字數。條在左、數字在右，一行。
    ///
    /// 積累色，不是瞳黃：這條說的是「你累積了多少」。整塊墨上現在只有按鈕是
    /// 瞳黃，而瞳黃的意思就是「下一步在這裡」。深青在墨上只有 3.04:1，所以
    /// 用淺的那一階 —— 墨面上一律用淺的。
    @ViewBuilder
    private var heroProgress: some View {
        let readout = self.decisions.completion
        HStack(spacing: Space.s3) {
            TujiProgressBar(
                progress: readout.ratio,
                track: .tujiPaper.opacity(0.2),
                fill: .tujiAccumulationSoft
            )
            // 它自己帶著「進行中」這個 label，不藏起來的話這一行會被唸成兩個元素。
            .accessibilityHidden(true)
            Text("\(readout.seen) / \(readout.total) 字")
                .font(.tujiBodySm(.strong))
                .foregroundStyle(.tujiAccumulationSoft)
                .fixedSize()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("主題進度"))
        .accessibilityValue(Text("\(readout.seen) / \(readout.total) 字"))
    }

    /// 一顆按鈕。右邊說待會要做什麼、幾個。
    @ViewBuilder
    private var studyButton: some View {
        switch self.decisions.call {
        case .pickThemes:
            NavigationLink(value: NavRoute.studyCategories) {
                StudyCallLabel(title: "選學習主題", trailing: nil)
            }
            .buttonStyle(StudyCallStyle())
            .tourAnchor(.heroCTAs)
        case .unknown:
            // stats 還沒到，所以說不出數字。按鈕照樣可以按：launcher 自己會抓
            // 佇列，抓到空的也自己有話說（「目前沒有可以練習的字」）。
            NavigationLink(value: NavRoute.studyLanding(mode: .review)) {
                StudyCallLabel(title: "背單字", trailing: nil)
            }
            .buttonStyle(StudyCallStyle())
            .tourAnchor(.heroCTAs)
        case let .study(mode, count):
            NavigationLink(value: NavRoute.studyLanding(mode: mode)) {
                StudyCallLabel(title: "背單字", trailing: Self.callCount(mode: mode, count: count))
            }
            .buttonStyle(StudyCallStyle())
            .tourAnchor(.heroCTAs)
        case .blocked:
            StudyCallLabel(title: "背單字", trailing: nil)
                .modifier(StudyCallDisabled())
                .tourAnchor(.heroCTAs)
        }
    }

    /// 「複習 12」／「新字 5」。模式併成一顆按鈕之後，這裡是唯一還看得到
    /// 待會要做哪一種的地方。
    private static func callCount(mode: StudyMode, count: Int) -> LocalizedStringKey {
        switch mode {
        case .review: LocalizedStringKey(tujiLocalized("複習 \(count)"))
        case .new: LocalizedStringKey(tujiLocalized("新字 \(count)"))
        }
    }

    /// 按鈕底下那一列：中間最多一行退路，右下角一顆記憶曲線。
    ///
    /// 這一列永遠在，即使沒有退路可給。好處是墨塊的高度不再隨當天的狀態上下
    /// 跳，壞處是沒有退路的日子多出 44pt —— 但那 44pt 本來就在最壞的情況裡，
    /// 底下 Moira 區離 tab bar 的距離是照「有退路」那天量的，所以把高度釘在
    /// 最大值不會讓已經量過的那一版變矮。
    private var heroFootRow: some View {
        ZStack(alignment: .bottomTrailing) {
            if let footer = self.decisions.footer {
                self.heroFooter(footer)
                    // 讓開右下角那顆圖示：這行字在最大字級下會長到撞上它。
                    .padding(.horizontal, 40)
            }
            self.reviewCurveButton
        }
    }

    /// 記憶曲線。
    ///
    /// 它解釋的是「為什麼今天先複習」，而解釋該待在被解釋的東西旁邊 —— 按鈕
    /// 上寫著「複習 26」，疑問就是在那裡冒出來的。
    private var reviewCurveButton: some View {
        Button { self.showingReviewCurve = true } label: {
            Image(systemName: "exclamationmark.circle")
                .font(.tujiIcon(16, weight: .semibold))
                .foregroundStyle(.tujiPaper.opacity(0.75))
                .frame(width: 44, height: 44)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        // 44 的打擊區把圖示往內推了 6pt。拉回去，跟標題列那兩顆 32 的圖示
        // 對齊同一條線 —— 多出來的那 6pt 落在墨塊自己的留白裡，順便讓真正的
        // 角落也點得到。
        .padding(.trailing, -6)
        .accessibilityLabel(Text("記憶曲線"))
    }

    /// 退路那一行。
    @ViewBuilder
    private func heroFooter(_ footer: TodayFooter) -> some View {
        switch footer {
        case .switchToNew:
            self.footerLink("學新字", route: .studyLanding(mode: .new))
        case .changeThemes:
            self.footerLink("換幾個主題", route: .studyCategories)
        case .unlockAllThemes:
            // 非會員學完了全部免費主題。「換幾個主題」會把他送去一整排鎖頭，
            // 再由鎖頭開付費頁 —— 這裡直接開。
            Button { self.presentPaywall() } label: {
                self.footerLabel("解鎖全部主題")
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity)
            .accessibilityHint(Text("開啟永久會員方案"))
        }
    }

    private func footerLink(_ title: LocalizedStringKey, route: NavRoute) -> some View {
        NavigationLink(value: route) {
            self.footerLabel(title)
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
    }

    /// 13pt 的字只有 18pt 高，所以打擊區靠上下的 padding 撐到 44pt。
    private func footerLabel(_ title: LocalizedStringKey) -> some View {
        Text(title)
            .font(.tujiLabel)
            .foregroundStyle(.tujiPaper.opacity(0.85))
            .underline()
            .padding(.horizontal, Space.s3)
            .padding(.vertical, 13)
            .contentShape(.rect)
    }

    // MARK: - 和 Moira 一起

    /// 併進來的助手首頁：一隻會呼吸的貓，加她的四個入口。
    ///
    /// 貓在入口正上方，所以四格只印標題不印說明 —— 她本人就說明了這一區是誰的。
    /// 說明還在 `AssistantHomeFeature.detail`，給 VoiceOver 唸。
    private var moiraSection: some View {
        VStack(spacing: Space.s3) {
            // 分頁之間切換不會 disappear，所以得明講她現在在不在前面。
            // 捲出畫面外不算 —— 那是幾秒的事，切到別的分頁是幾分鐘的事。
            AnimatedMascot(paused: self.navigator.selected != .today)
                .frame(height: 236)
                // 她的 580 單位畫布底下有一截是空的（接觸陰影之後還剩約 24pt），
                // 在助手首頁那是最後一個元素所以沒差，在這裡它把四格往下推。
                .padding(.bottom, -24)

            MoiraFeatureBand()
        }
        .tourAnchor(.assistant)
    }

    // MARK: - 主題格子

    /// One theme tile's height, scaled with the text size. Only the window's
    /// floor is computed from it, so an estimate is enough — a measurement
    /// would have to happen before the tiles it measures are laid out.
    @ScaledMetric(relativeTo: .body) private var themeTileHeight: CGFloat = 68

    /// The height the page's measurement leaves for the strip. Nil until the
    /// first pass, which is what `themeStripHeight`'s floor stands in for.
    @State private var themeStripSpace: CGFloat?

    /// 格子，沒有標頭。
    ///
    /// 標頭本來是「主題」加一行底線的「更換學習主題」。兩個都搬進墨塊了：標題
    /// 說的是同一組主題，⚙ 做的是同一件事。底下那張「還沒選學習主題」的提示卡
    /// 也一起刪了 —— 墨塊的 `.pickThemes` 整塊就是那張卡。
    @ViewBuilder
    private var themesGrid: some View {
        let tiles = self.themeTiles
        if !tiles.isEmpty {
            ScrollView(.vertical) {
                LazyVGrid(
                    columns: [
                        GridItem(.flexible(), spacing: Space.s2),
                        GridItem(.flexible(), spacing: Space.s2)
                    ],
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
                .padding(.horizontal, Space.s4)
            }
            .frame(height: self.themeStripHeight)
        }
    }

    /// What the page's measurement left for the strip, clamped to a floor of two
    /// rows and the gap between them — below that the page scrolls instead, the
    /// way it does at the largest text sizes.
    private var themeStripHeight: CGFloat {
        max(self.themeStripSpace ?? 0, self.themeTileHeight * 2 + Space.s2)
    }

    /// Exactly the selected themes (that have words).
    private var themeTiles: [TujiCategory] {
        let presentIds = Set(self.words.categories)
        let known = self.categories.categories.filter { presentIds.contains($0.id) }
        let selected = Set(StudyCategoryDefaults.effective(
            selected: self.settings.current.studyCategories,
            studyable: StudyCategoryDefaults.liveStudyable
        ))
        guard !selected.isEmpty else { return [] }
        return known.filter { selected.contains($0.id) }
    }

    /// Completion state for a theme tile. The rule itself lives on ThemeStatus
    /// so 圖鑑·官方's shelf asks the same question the same way.
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

/// 墨塊上那顆按鈕的內容：左邊一個動詞，右邊（有話說的時候）待會要做什麼。
private struct StudyCallLabel: View {
    let title: LocalizedStringKey
    let trailing: LocalizedStringKey?

    var body: some View {
        HStack(spacing: Space.s3) {
            Text(self.title)
                .font(.tujiH3)
            Spacer(minLength: Space.s2)
            if let trailing = self.trailing {
                Text(trailing)
                    .font(.tujiBodySm(.strong))
                    .opacity(0.75)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, Space.s3)
        .padding(.horizontal, Space.s3 + 4)
    }
}

/// 瞳黃底、墨字。按下去只換底色，什麼都不動 —— BBtn 的同一條規則。
private struct StudyCallStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(.tujiInk)
            .background(configuration.isPressed ? Color.tujiCurrentDeep : Color.tujiCurrent)
    }
}

/// 反灰。沿用原本 `HeroPillStyle` 的兩個值 —— 這是 app 既有的「關掉了」的樣子。
private struct StudyCallDisabled: ViewModifier {
    func body(content: Content) -> some View {
        content
            .foregroundStyle(.tujiPaper.opacity(0.4))
            .background(Color.tujiPaper.opacity(0.08))
            .accessibilityAddTraits(.isButton)
            .accessibilityRemoveTraits(.isButton)
    }
}

#Preview("Signed in") {
    NavigationStack {
        TodayView()
            .environment(WordsStore.shared)
            .environment(CategoriesStore.shared)
            .environment(LocalCache.shared)
            .environment(ProgressStore.shared)
            .environment(StudyStatsStore.shared)
            .environment(SettingsStore.shared)
            .environment(MasteryStore.shared)
            .environment(AuthService.shared)
            .environment(CheckInModel())
    }
}
