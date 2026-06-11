// Category landing page (§III.G).
//
// Hero card with emoji glyph + Chinese / English names, then the 2-col
// grid of every word in that category. Tap a tile to push WordDetailView
// (handled at MainTabsView's NavigationStack level via NavRoute).

import SwiftUI

struct CategoryView: View {
    let id: String

    @Environment(WordsStore.self) private var words
    @Environment(CategoriesStore.self) private var categories

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
            VStack(alignment: .leading, spacing: Space.s3) {
                Text(c.emoji).font(.system(size: 56))
                Text(c.nameZh)
                    .font(.tujiH2)
                    .foregroundStyle(.tujiInk)
                Text(c.name)
                    .font(.tujiCaption)
                    .foregroundStyle(.tujiInk3)
                    .tracking(2)
                if let desc = c.description, !desc.isEmpty {
                    Text(desc)
                        .font(.tujiBody)
                        .foregroundStyle(.tujiInk2)
                        .padding(.top, Space.s1)
                }
            }
            .padding(Space.s5)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.tujiTealSoft, in: .rect(cornerRadius: Radius.xl))
        } else {
            VStack(alignment: .leading, spacing: Space.s3) {
                Text("📚").font(.system(size: 56))
                Text(self.id)
                    .font(.tujiH2)
                    .foregroundStyle(.tujiInk)
            }
            .padding(Space.s5)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.tujiTealSoft, in: .rect(cornerRadius: Radius.xl))
        }
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
            VStack(spacing: Space.s2) {
                Mascot(pose: .sleep, size: 64)
                Text("這個主題還沒有字")
                    .font(.tujiBody)
                    .foregroundStyle(.tujiInk3)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, Space.s12)
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
                        WordTile(word: word)
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
    }
}
