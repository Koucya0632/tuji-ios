// 主題 — the index of every theme in the dictionary.
//
// This replaces the second chip row that used to sit under 圖鑑's source
// filter. A horizontal strip of chips is fine for five themes and unusable at
// forty: you cannot see what is on offer without scrolling blindly, and the
// row's height is charged to every visit whether or not you want to filter.
//
// A theme already has a page of its own (CategoryView, with its bleeding hero),
// so the answer to "let me browse by theme" is to send the user there rather
// than to filter the flat grid in place.

import SwiftUI

struct CategoryIndexView: View {
    @Environment(WordsStore.self) private var words
    @Environment(CategoriesStore.self) private var categories
    @Environment(MasteryStore.self) private var mastery
    @Environment(ProgressStore.self) private var progress

    var body: some View {
        VStack(spacing: 0) {
            TujiNavBar(leading: .back)
            self.list
        }
        .background(.tujiPaper)
        .navigationTitle("主題")
        .toolbar(.hidden, for: .navigationBar)
        .task {
            await self.categories.loadIfNeeded()
            await self.words.loadIfNeeded()
            await self.mastery.loadIfNeeded()
        }
    }

    private var list: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.s4) {
                Text("主題")
                    .font(.tujiH2)
                    .foregroundStyle(.tujiInk)

                // The catalogue arrives over the network, and a VStack that
                // renders to nothing takes its `.task` with it — so the loading
                // state has to be a real view, not an empty branch.
                if self.visibleCategories.isEmpty {
                    if self.categories.categories.isEmpty {
                        HStack {
                            TujiPageLoading()
                            Text("載入主題中…")
                                .font(.tujiLabel)
                                .foregroundStyle(.tujiInk3)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, Space.s4)
                    } else {
                        MascotEmptyState(pose: .sleep, title: "還沒有主題", compact: true)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, Space.s5)
                    }
                } else {
                    self.grid
                }
            }
            .padding(.horizontal, Space.s4)
            .padding(.top, Space.s3)
            .padding(.bottom, Space.s6)
        }
    }

    private var grid: some View {
        LazyVGrid(
            columns: [
                GridItem(.flexible(), spacing: Space.s2, alignment: .top),
                GridItem(.flexible(), spacing: Space.s2, alignment: .top)
            ],
            spacing: Space.s2
        ) {
            ForEach(self.visibleCategories) { c in
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

    private var visibleCategories: [TujiCategory] {
        Self.visibleThemeCategories(
            from: self.categories.categories,
            presentIds: Set(self.words.categories)
        )
    }

    private func themeStatus(for id: String) -> ThemeStatus {
        ThemeStatus.of(
            words: self.words.byCategory(id),
            masteryScore: { self.mastery.score(for: $0) },
            progress: self.progress.categoryProgress,
            categoryId: id
        )
    }

    /// Themes only, and only ones with words behind them. `custom` and
    /// `community` are rows in the categories table but they are *sources* —
    /// where a word came from — not themes, and they have their own filter on
    /// 圖鑑. Listing them here would present one filter twice under two
    /// different meanings.
    ///
    /// Internal so a test can exercise the rule without a view.
    static func visibleThemeCategories(
        from categories: [TujiCategory],
        presentIds: Set<String>
    )
        -> [TujiCategory]
    {
        categories.filter {
            $0.id != "custom" && $0.id != "community" && presentIds.contains($0.id)
        }
    }
}

#Preview {
    NavigationStack {
        CategoryIndexView()
            .environment(WordsStore.shared)
            .environment(CategoriesStore.shared)
            .environment(MasteryStore.shared)
            .environment(ProgressStore.shared)
    }
}
