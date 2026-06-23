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
        }
        .background(.tujiBg)
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
        VStack(alignment: .leading, spacing: Space.s5) {
            self.hero
            Section {
                self.grid(width: width)
            } header: {
                self.gridHeader
            }
        }
        .frame(width: width - Space.s6 * 2, alignment: .leading)
        .padding(.horizontal, Space.s6)
        .padding(.top, Space.s5)
        .padding(.bottom, Space.s12)
        .frame(width: width, alignment: .leading)
    }

    @ViewBuilder
    private var hero: some View {
        if let c = category {
            ZStack(alignment: .leading) {
                self.categoryArtwork(c)

                LinearGradient(
                    colors: [
                        Color.tujiTealSoft.opacity(0.98),
                        Color.tujiTealSoft.opacity(0.82),
                        Color.tujiTealSoft.opacity(0.08)
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )

                VStack(alignment: .leading, spacing: Space.s3) {
                    Text("主題分類")
                        .font(.tujiOverline)
                        .tracking(2)
                        .foregroundStyle(.tujiTeal)

                    Text(c.nameZh)
                        .font(.tujiH2)
                        .foregroundStyle(.tujiInk)

                    Text(c.name)
                        .font(.tujiCaption)
                        .foregroundStyle(.tujiInk3)
                        .tracking(2)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("分類說明")
                            .font(.system(size: 11, weight: .heavy))
                            .foregroundStyle(.tujiInk3)

                        Text(self.categoryDescription(c))
                            .font(.tujiBody)
                            .foregroundStyle(.tujiInk2)
                            .lineLimit(3)
                    }
                    .padding(.top, Space.s2)
                }
                .padding(Space.s5)
                .frame(maxWidth: 220, alignment: .leading)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 260)
            .background(.tujiTealSoft)
            .clipShape(RoundedRectangle(cornerRadius: Radius.xl))
        } else {
            VStack(alignment: .leading, spacing: Space.s3) {
                Image(systemName: "square.grid.2x2.fill")
                    .font(.system(size: 32, weight: .bold))
                    .foregroundStyle(.tujiTeal)
                Text(self.id)
                    .font(.tujiH2)
                    .foregroundStyle(.tujiInk)
                Text("分類說明")
                    .font(.system(size: 11, weight: .heavy))
                    .foregroundStyle(.tujiInk3)
                Text("探索這個主題的常用單字")
                    .font(.tujiBody)
                    .foregroundStyle(.tujiInk2)
            }
            .padding(Space.s5)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.tujiTealSoft, in: .rect(cornerRadius: Radius.xl))
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
                    Color.tujiTealSoft
                }
            }
            .pipeline(.shared)
        } else {
            Color.tujiTealSoft
        }
    }

    private func categoryDescription(_ category: TujiCategory) -> String {
        guard let description = category.description,
              !description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            return "探索與\(category.nameZh)相關的常用單字"
        }
        return description
    }

    private var gridHeader: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("單字")
                .font(.tujiOverline)
                .tracking(2)
                .foregroundStyle(.tujiTeal)
            Spacer()
            Text("\(self.filteredWords.count)")
                .font(.system(size: 13, weight: .heavy))
                .foregroundStyle(.tujiInk3)
        }
        .padding(.vertical, Space.s2)
    }

    @ViewBuilder
    private func grid(width: CGFloat) -> some View {
        let words = self.filteredWords
        if words.isEmpty {
            MascotEmptyState(
                pose: .sleep,
                title: "這個主題還沒有字",
                compact: true
            )
            .frame(maxWidth: .infinity)
            .padding(.vertical, Space.s8)
        } else {
            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: Space.s3),
                    GridItem(.flexible(), spacing: Space.s3)
                ],
                spacing: Space.s3
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
