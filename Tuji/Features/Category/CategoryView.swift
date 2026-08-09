// Category landing page (§III.G).
//
// Illustrated hero card with Chinese / English names + a category
// explanation, then the 2-col grid of every word in that category. Tap a
// tile to push WordDetailView (handled at MainTabsView's NavigationStack
// level via NavRoute).

import Nuke
import NukeUI
import SwiftUI

struct CategoryView: View {
    let id: String

    @Environment(WordsStore.self) private var words
    @Environment(CategoriesStore.self) private var categories
    @Environment(MasteryStore.self) private var mastery

    var body: some View {
        GeometryReader { geo in
            ScrollView {
                self.content(width: geo.size.width)
            }
            // Floats over the bleeding hero rather than taking a row above it,
            // so the page still opens with the picture.
            .overlay(alignment: .topLeading) {
                TujiNavBar(leading: .back)
            }
        }
        .background(.tujiPaper)
        .navigationTitle(self.category?.nameZh ?? self.id)
        .toolbar(.hidden, for: .navigationBar)
        .task {
            await self.categories.loadIfNeeded()
            await self.words.loadIfNeeded()
            await self.mastery.loadIfNeeded()
        }
    }

    // MARK: - Bits

    private var category: TujiCategory? {
        self.categories.find(id: self.id)
    }

    private var filteredWords: [CardWord] {
        self.words.byCategory(self.id)
    }

    private func content(width: CGFloat) -> some View {
        // The hero bleeds, so no shared horizontal padding — each section below
        // carries its own. The grid was the one that never did: its tiles ran
        // to both screen edges while the description and the 單字 count above
        // them sat inset, so the page looked like it had lost its margin.
        VStack(alignment: .leading, spacing: Space.s4) {
            self.hero
            Section {
                self.grid.padding(.horizontal, Space.s4)
            } header: {
                self.gridHeader.padding(.horizontal, Space.s4)
            }
        }
        .padding(.bottom, Space.s6)
        .frame(width: width, alignment: .leading)
    }

    /// Full-bleed 16:9 photograph with the text laid over its lower edge.
    ///
    /// Before, the artwork sat in a rounded card under a near-opaque pale teal
    /// wash, with the text crammed into the left 220pt — so the picture was
    /// neither visible nor doing any work, and the card had no weight either.
    /// Now the photo is actually seen, the copy has a readable band of its own,
    /// and the top of the screen carries something that is not paper, which
    /// echoes the ink block on 今天.
    @ViewBuilder
    private var hero: some View {
        if let c = self.category {
            ZStack(alignment: .bottomLeading) {
                self.categoryArtwork(c)

                // One-way scrim for legibility, not decoration: ink at the
                // bottom fading to nothing by 60% height.
                LinearGradient(
                    colors: [.clear, Color.tujiInk.opacity(0.7)],
                    startPoint: .top,
                    endPoint: .bottom
                )

                VStack(alignment: .leading, spacing: Space.s1) {
                    Text("主題分類")
                        .font(.tujiLabel)
                        .tracking(0.5)
                        .foregroundStyle(.tujiPaper.opacity(0.6))
                    Text(c.nameZh)
                        .font(.tujiH1)
                        .foregroundStyle(.tujiPaper)
                    Text(c.name)
                        .font(.tujiBodySm)
                        .foregroundStyle(.tujiPaper.opacity(0.6))
                }
                .padding(Space.s4)
            }
            .frame(maxWidth: .infinity)
            .aspectRatio(16.0 / 9.0, contentMode: .fill)
            .clipped()

            if !self.categoryDescription(c).isEmpty {
                Text(verbatim: self.categoryDescription(c))
                    .font(.tujiBody)
                    .foregroundStyle(.tujiInk2)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, Space.s4)
            }
        } else {
            VStack(alignment: .leading, spacing: Space.s2) {
                Text(self.id)
                    .font(.tujiH1)
                    .foregroundStyle(.tujiInk)
                Text("探索這個主題的常用單字")
                    .font(.tujiBody)
                    .foregroundStyle(.tujiInk2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Space.s4)
            .padding(.top, Space.s4)
        }
    }

    @ViewBuilder
    private func categoryArtwork(_ category: TujiCategory) -> some View {
        if category.id == "kitchen" {
            Image("category-kitchen-hero")
                .resizable()
                .scaledToFill()
        } else if let url = category.imageURL {
            LazyImage(url: url) { state in
                if let image = state.image {
                    image.resizable().scaledToFill()
                } else {
                    TujiImagePlaceholder()
                }
            }
            .pipeline(.shared)
        } else {
            Color.tujiPaper2
        }
    }

    private func categoryDescription(_ category: TujiCategory) -> String {
        guard let description = category.description,
              !description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            return tujiLocalized("探索與\(category.nameZh)相關的常用單字")
        }
        return description
    }

    private var gridHeader: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("單字")
                .font(.tujiLabel)
                .tracking(2)
                .foregroundStyle(.tujiBrandSecondary)
            Spacer()
            Text("\(self.filteredWords.count)")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.tujiInk3)
        }
        .padding(.vertical, Space.s2)
    }

    @ViewBuilder
    private var grid: some View {
        let words = self.filteredWords
        if words.isEmpty {
            MascotEmptyState(
                pose: .sleep,
                title: "這個主題還沒有字",
                compact: true
            )
            .frame(maxWidth: .infinity)
            .padding(.vertical, Space.s5)
        } else {
            LazyVGrid(
                columns: CardsListView.gridColumns,
                spacing: Space.s4
            ) {
                ForEach(words) { word in
                    NavigationLink(value: NavRoute.wordDetail(id: word.id)) {
                        WordTile(
                            word: word,
                            showMastery: true,
                            masteryScore: self.mastery.score(for: word.id),
                            nextReviewDate: self.mastery.nextReviewDate(for: word.id)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

#Preview {
    NavigationStack {
        CategoryView(id: "kitchen")
            .environment(WordsStore.shared)
            .environment(CategoriesStore.shared)
            .environment(MasteryStore.shared)
    }
}
