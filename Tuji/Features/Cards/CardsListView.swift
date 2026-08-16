// 2-column grid of every word, filterable by where the word came from.
//
// One filter row, not two. The theme row that used to sit under it is gone:
// chips are a horizontal strip, and a strip cannot be browsed once the
// catalogue has forty themes in it. Theme browsing moved to CategoryIndexView,
// reachable from the count row — and picking a theme there lands on the theme's
// own page, which is a better answer than filtering this grid in place.

import SwiftUI

struct CardsListView: View {
    @Environment(WordsStore.self) private var store
    @Environment(MasteryStore.self) private var mastery
    @Environment(LocalCache.self) private var cache
    @Environment(AuthService.self) private var auth
    @Environment(TabNavigator.self) private var navigator

    private var isGuest: Bool {
        if case .signedIn = self.auth.state { return false }
        return true
    }

    /// A source the navigation layer wants shown (a `tuji://favorites` link).
    /// Consumed once and cleared, so it never fights a later manual pick.
    @Binding var sourceRequest: CardsSource?

    /// Opens on 官方 rather than on nothing. The tab has to open *somewhere*,
    /// and an unselected row reads as "no filter is available" — it also hides
    /// 主題, which only appears under 官方. `nil` (everything) is still
    /// reachable: tapping the lit chip clears it. See CardsSource.
    @State private var source: CardsSource? = .official
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
        .task {
            await self.store.loadIfNeeded()
            await self.mastery.loadIfNeeded()
        }
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
                    .font(.system(size: 18, weight: .bold))
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
                    ForEach(CardsSource.available(isGuest: self.isGuest)) { value in
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
    /// source has. 主題 belongs to 官方 because a theme only ever describes a
    /// dictionary word: the ones you photographed and the ones you took in from
    /// the community have no theme to browse by. 管理 belongs to 我做的 for the
    /// same reason, and it keeps 圖鑑管理 out of the nav bar (already full) and
    /// out of 我 (which is no longer a directory). The two are mutually
    /// exclusive, so the row never carries both.
    private var countRow: some View {
        HStack(spacing: Space.s3) {
            // Reuses the existing `%lld 字` key rather than minting `%lld 個字`
            // beside it — one concept, one string.
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
            case .official:
                NavigationLink(value: NavRoute.categoryIndex) {
                    self.rowAction("主題 →")
                }
                .buttonStyle(.plain)
            case .taken, .bookmarked, nil:
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

    private var emptyTitle: LocalizedStringKey {
        switch self.source {
        case .bookmarked: "還沒有書籤"
        case .mine: "還沒有自製圖鑑"
        case .taken: "還沒有收進的字"
        case .official, nil: "這個分類還沒有字"
        }
    }

    private var emptyHint: LocalizedStringKey? {
        switch self.source {
        case .bookmarked: "你加書籤的字會出現在這裡"
        case .mine: "用右上角的相機拍一張，就會多一張卡片"
        case .taken: "在物見收進的字會出現在這裡"
        case .official, nil: nil
        }
    }

    /// Tapping the chip that is already on clears it, which is how the grid
    /// gets back to "everything" without a 全部 chip standing in for it.
    private func sourceChip(_ value: CardsSource) -> some View {
        let selected = self.source == value
        return Button {
            self.source = selected ? nil : value
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
        if self.store.loading, self.store.words.isEmpty {
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
        } else if let error = store.lastError, self.store.words.isEmpty {
            TujiErrorState(
                title: "載不到單字",
                message: error.localizedDescription
            ) {
                BBtn(title: "重試", fullWidth: false, action: {
                    Task { await self.store.reload() }
                })
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, Space.s4)
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
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.tujiInk3)
                            .padding(.vertical, Space.s3)
                    }
                    .padding(.top, Space.s3)
                } else if self.page.matchCount == 0 {
                    // The message has to name what is actually empty. With a
                    // source filter on, "這個分類還沒有字" is simply wrong — the
                    // user filtered by where words come from, not by theme —
                    // and C.6 asks empty states to say what *will* be here.
                    MascotEmptyState(pose: .sleep, title: self.emptyTitle, message: self.emptyHint)
                        .tujiEmptyStatePlacement()
                        .frame(minHeight: 320)
                }
            }
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
