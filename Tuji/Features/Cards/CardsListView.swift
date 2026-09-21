// 2-column grid, filterable by where a word came from.
//
// One filter row, not two. The theme row that used to sit under it is gone:
// chips are a horizontal strip, and a strip cannot be browsed once the
// catalogue has forty themes in it.
//
// 官方 does not show words at all — it shows the themes, each with its cover,
// and the words behind one are on the theme's own page (CategoryView). The
// dictionary is 757 words long; a flat grid of it was a list you paged through
// sixty at a time, with the themes hidden behind a small 主題 → link that had
// its own screen. That screen is retired: this *is* it, at the top of the tab
// where browsing starts. The other three sources still show word tiles — a
// photographed card or one taken in from 物見 belongs to no theme.

import SwiftUI

struct CardsListView: View {
    @Environment(WordsStore.self) private var store
    @Environment(CategoriesStore.self) private var categories
    @Environment(ProgressStore.self) private var progress
    @Environment(MasteryStore.self) private var mastery
    @Environment(LocalCache.self) private var cache
    @Environment(AuthService.self) private var auth
    @Environment(TabNavigator.self) private var navigator

    /// A source the navigation layer wants shown (a `tuji://favorites` link).
    /// Consumed once and cleared, so it never fights a later manual pick.
    @Binding var sourceRequest: CardsSource?

    /// Always one, never none. The row used to be clearable — tapping the lit
    /// chip dropped the filter and showed everything — which left the row with
    /// no chip on and nothing saying why. See CardsSource.
    @State private var source: CardsSource = .official
    @State private var visibleCount: Int = CardsListPaging.pageSize
    @State private var peekWord: CardWord?
    @State private var pushAfterDismiss: String?

    /// `alignment: .top` is the whole point. A GridItem with no alignment
    /// centres its cell inside the row, so the moment one word wrapped to two
    /// lines its shorter neighbour dropped by half the height difference and
    /// the two columns of photographs stopped lining up.
    static let gridColumns = [
        GridItem(.flexible(), spacing: Space.s2, alignment: .top),
        GridItem(.flexible(), spacing: Space.s2, alignment: .top)
    ]

    var body: some View {
        VStack(spacing: 0) {
            self.header
            self.chipRow
            self.content
        }
        .background(.tujiPaper)
        // Metadata only (VoiceOver, back-button label on pushed screens,
        // multitasking window title) — `header` below is the visible title,
        // so the system nav bar itself stays hidden.
        .navigationTitle("圖鑑")
        .toolbar(.hidden, for: .navigationBar)
        // 官方's tiles carry 完成 / 全精通, so this screen reads progress and
        // mastery as well as the dictionary — the same set 主題 used to warm,
        // asked for by name instead of hand-written here. (A hand-written
        // `.task` is what left the old 主題 screen rendering 完成 from a store
        // it never loaded; see AccumulationLoading.)
        .warmsAccumulation(.themeIndex, isGuest: self.auth.isGuest)
        .onChange(of: self.sourceRequest, initial: true) { _, requested in
            guard let requested else { return }
            self.source = requested
            self.sourceRequest = nil
        }
        // 看更多 pushes a *route*, so a `saved:` tile opens the same screen
        // whether it was tapped or long-pressed. It used to construct
        // WordDetailView here and skip the route table's `saved:` branch — two
        // gestures on one tile, two different screens.
        .sheet(item: self.$peekWord, onDismiss: {
            guard let id = self.pushAfterDismiss else { return }
            self.pushAfterDismiss = nil
            self.navigator.push(.wordDetail(id: id))
        }) { word in
            WordPeekSheet(word: word) {
                self.pushAfterDismiss = word.id
                self.peekWord = nil
            }
        }
    }

    // MARK: - Bits

    /// Actions only. The title used to sit on the left of this row and said
    /// "圖鑑" — the same word the tab directly below it says, lit, at the moment
    /// you are looking at it. 我 already works this way (`MeView`): the first
    /// real content is the title, and the bar carries nothing but what you can
    /// do from here.
    ///
    /// 搜尋 is all that is left of it: 拍照 used to sit here too, and it was the
    /// app's headline feature reachable from exactly one screen, in the corner
    /// furthest from the thumb. It is in the tab bar now (`CaptureBarButton`).
    private var header: some View {
        HStack {
            Spacer()
            NavigationLink(value: NavRoute.search(query: nil)) {
                Image(systemName: "magnifyingglass")
                    .font(.tujiIcon(18, weight: .bold))
                    .foregroundStyle(.tujiInk2)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, Space.s4)
        .padding(.top, Space.s3)
        .padding(.bottom, Space.s3)
    }

    private var chipRow: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Space.s2) {
                    ForEach(CardsSource.available(isGuest: self.auth.isGuest)) { value in
                        self.sourceChip(value)
                    }
                }
                .padding(.horizontal, Space.s4)
            }

            self.countRow
        }
        .padding(.bottom, Space.s3)
    }

    /// Count on the left, one action on the right — whichever the current
    /// source has. Only 我做的 has one now: 管理 keeps 圖鑑管理 out of the nav
    /// bar (already full) and out of 我 (which is no longer a directory). 官方
    /// used to carry 主題 → beside it; the themes are the grid itself now, so
    /// the link would point at the screen the user is already on.
    ///
    /// The count stays in words even on 官方 — 757 字 is what the official
    /// half of the catalogue has, which is the number worth knowing, and it
    /// reuses the one `%lld 字` key rather than minting a second concept.
    private var countRow: some View {
        HStack(spacing: Space.s3) {
            Text(tujiLocalized("\(self.page.matchCount) 字"))
                .font(.tujiLabel)
                .tracking(0.5)
                .foregroundStyle(.tujiInk3)
            Spacer()
            switch self.source {
            case .mine:
                NavigationLink(value: NavRoute.atlasManage) {
                    self.rowAction("管理 →")
                }
                .buttonStyle(.plain)
            case .official, .taken, .bookmarked:
                EmptyView()
            }
        }
        .padding(.horizontal, Space.s4)
        .padding(.top, Space.s1)
    }

    private func rowAction(_ title: LocalizedStringKey) -> some View {
        Text(title)
            .font(.tujiLabel)
            .tracking(0.5)
            .foregroundStyle(.tujiInk)
            .underline()
    }

    /// 官方 empties differently from the other three: what is missing is the
    /// catalogue itself, not a word of yours, so it says so in the theme grid's
    /// own words.
    private var emptyTitle: LocalizedStringKey {
        switch self.source {
        case .bookmarked: "還沒有書籤"
        case .mine: "還沒有自製圖鑑"
        case .taken: "還沒有收進的字"
        case .official: "還沒有主題"
        }
    }

    private var emptyHint: LocalizedStringKey? {
        switch self.source {
        case .bookmarked: "你加書籤的字會出現在這裡"
        case .mine: "用底下中間的相機拍一張，就會多一張卡片"
        case .taken: "在物見收進的字會出現在這裡"
        case .official: nil
        }
    }

    /// Tapping the lit chip does nothing: one source is always in effect, so
    /// there is no state for it to clear to.
    private func sourceChip(_ value: CardsSource) -> some View {
        let selected = self.source == value
        return Button {
            guard !selected else { return }
            self.source = value
            self.visibleCount = CardsListPaging.pageSize
        } label: {
            Text(value.title)
                .font(.tujiLabel)
                .tracking(0.5)
                .foregroundStyle(selected ? Color.tujiPaper : .tujiInk2)
                .padding(.horizontal, Space.s3)
                .frame(height: 36)
                .background(selected ? Color.tujiInk : .tujiPaper2)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }

    @ViewBuilder
    private var content: some View {
        if self.isLoadingFirstContent {
            // Two-column skeleton in the shape of the grid that is coming —
            // the point of a skeleton over a spinner is that the layout does
            // not jump when the real tiles land.
            LazyVGrid(
                columns: Self.gridColumns,
                spacing: Space.s4
            ) {
                ForEach(0..<6, id: \.self) { _ in
                    VStack(alignment: .leading, spacing: Space.s2) {
                        TujiImagePlaceholder().aspectRatio(1, contentMode: .fit)
                        TujiSkeleton(width: 72, height: 14)
                    }
                }
            }
            .padding(.horizontal, Space.s4)
            .padding(.top, Space.s3)
            .frame(maxWidth: .infinity, alignment: .top)
            .accessibilityLabel(Text("載入中"))
        } else if let error = self.blockingError {
            TujiErrorState(
                title: self.source.showsThemes ? "載入失敗" : "載不到單字",
                message: tujiUserMessage(for: error)
            ) {
                BBtn(title: "重試", fullWidth: false, action: {
                    Task { await self.reloadContent() }
                })
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, Space.s4)
        } else if self.source.showsThemes {
            self.themeShelf
        } else {
            ScrollView {
                LazyVGrid(
                    columns: Self.gridColumns,
                    spacing: Space.s4
                ) {
                    // Cards still being made sit at the head of the grid, in the
                    // same columns as the finished ones — they *are* cards, and
                    // the horizontal strip that used to announce them above the
                    // grid cost a permanent band at the top of the tab.
                    AtlasCaptureQueueTiles()
                    ForEach(self.visibleWords) { word in
                        NavigationLink(value: NavRoute.wordDetail(id: word.id)) {
                            WordTile(
                                word: word,
                                showMastery: true,
                                masteryScore: self.mastery.score(for: word.id)
                            )
                        }
                        .buttonStyle(.plain)
                        .onLongPressGesture(minimumDuration: 0.35) {
                            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                            self.peekWord = word
                        }
                    }
                }
                .padding(.horizontal, Space.s4)

                if self.canShowMore {
                    Button {
                        self.visibleCount += CardsListPaging.pageSize
                    } label: {
                        Text("顯示更多")
                            .font(.tujiBodySm(.strong))
                            .foregroundStyle(.tujiInk3)
                            .padding(.vertical, Space.s3)
                    }
                    .padding(.top, Space.s3)
                } else if self.page.matchCount == 0 {
                    // The message has to name what is actually empty. A source
                    // filter empties for a reason of its own — the user filtered
                    // by where words come from, not by theme — and C.6 asks
                    // empty states to say what *will* be here.
                    MascotEmptyState(pose: .sleep, title: self.emptyTitle, message: self.emptyHint)
                        .tujiEmptyStatePlacement()
                        .frame(minHeight: 320)
                }
            }
        }
    }

    /// 官方: the themes, each with its cover.
    ///
    /// No 顯示更多 — the catalogue is a dozen themes, not 757 words — and no
    /// capture-queue tiles either: a card being made is not a theme, and it
    /// still heads the grid on 我做的, where it was always going to land.
    private var themeShelf: some View {
        ScrollView {
            LazyVGrid(columns: Self.gridColumns, spacing: Space.s2) {
                ForEach(self.themes) { c in
                    NavigationLink(value: NavRoute.categoryDetail(id: c.id)) {
                        CategoryCoverTile(
                            category: c,
                            wordCount: self.store.byCategory(c.id).count,
                            status: self.themeStatus(for: c.id)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, Space.s4)

            if self.themes.isEmpty {
                MascotEmptyState(pose: .sleep, title: self.emptyTitle, message: self.emptyHint)
                    .tujiEmptyStatePlacement()
                    .frame(minHeight: 320)
            }
        }
    }

    /// Which categories are themes is `ThemeCatalog`'s answer, not this
    /// screen's — 今天's strip asks a different question (the ones *you* picked)
    /// and the two must not drift into two rules.
    private var themes: [TujiCategory] {
        ThemeCatalog.themes(
            from: self.categories.categories,
            presentIds: Set(self.store.categories)
        )
    }

    /// The badge rule, asked the same way 今天 asks it.
    private func themeStatus(for id: String) -> ThemeStatus {
        ThemeStatus.of(
            words: self.store.byCategory(id),
            masteryScore: { self.mastery.score(for: $0) },
            progress: self.progress.categoryProgress,
            categoryId: id
        )
    }

    /// The skeleton covers whichever store this source is waiting on: the
    /// dictionary for the word grid, and the catalogue too for the shelf — the
    /// tiles need a name and a cover before they are worth drawing.
    private var isLoadingFirstContent: Bool {
        if self.store.loading, self.store.words.isEmpty { return true }
        return self.source.showsThemes
            && self.categories.categories.isEmpty
            && self.categories.loading
    }

    /// An error is only worth the whole screen when there is nothing behind it.
    private var blockingError: Error? {
        if let error = self.store.lastError, self.store.words.isEmpty { return error }
        if self.source.showsThemes, self.categories.categories.isEmpty {
            return self.categories.lastError
        }
        return nil
    }

    private func reloadContent() async {
        await self.store.reload()
        if self.source.showsThemes {
            await self.categories.reload()
        }
    }

    /// One read of the filter + page window; see `CardsListPaging`.
    private var page: CardsListPage {
        CardsListPaging.page(
            words: self.store.words,
            source: self.source,
            isBookmarked: self.cache.isFavorite,
            visibleCount: self.visibleCount
        )
    }

    private var visibleWords: [CardWord] {
        self.page.words
    }

    private var canShowMore: Bool {
        self.page.canShowMore
    }
}

#Preview {
    NavigationStack {
        CardsListView(sourceRequest: .constant(nil))
            .environment(WordsStore.shared)
            .environment(MasteryStore.shared)
            .environment(TabNavigator())
    }
}
