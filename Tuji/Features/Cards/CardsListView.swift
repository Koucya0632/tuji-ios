// 2-column grid of every word, filterable by category chip.
//
// Chips show the localized zh name from CategoriesStore. When a specific
// chip is selected (not 全部) we also surface a "前往主題詳細頁 →" CTA so
// the user can jump to the dedicated CategoryView landing page from the
// list view.

import SwiftUI

struct CardsListView: View {
    @Environment(WordsStore.self) private var store
    @Environment(CategoriesStore.self) private var categories

    @State private var selectedCategory: String?
    @State private var visibleCount: Int = 60
    @State private var peekWord: CardWord?
    @State private var pushAfterDismiss: String?

    private let pageSize: Int = 60

    var body: some View {
        VStack(spacing: 0) {
            self.header
            self.chipRow
            if self.selectedCategory != nil {
                self.categoryDetailCTA
            }
            self.content
        }
        .background(.tujiBg)
        .task {
            await self.store.loadIfNeeded()
            await self.categories.loadIfNeeded()
        }
        .sheet(item: self.$peekWord) { word in
            WordPeekSheet(word: word) {
                self.pushAfterDismiss = word.id
                self.peekWord = nil
            }
        }
        .navigationDestination(item: self.$pushAfterDismiss) { id in
            WordDetailView(id: id)
        }
    }

    // MARK: - Bits

    private var header: some View {
        HStack {
            Text("圖鑑")
                .font(.tujiH2)
                .foregroundStyle(.tujiInk)
            Spacer()
            NavigationLink(value: NavRoute.search) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(.tujiInk2)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, Space.s6)
        .padding(.top, Space.s4)
        .padding(.bottom, Space.s3)
    }

    private var chipRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Space.s2) {
                self.chip(label: "全部", value: nil)
                ForEach(self.chipCategories, id: \.id) { c in
                    self.chip(label: c.nameZh, value: c.id)
                }
            }
            .padding(.horizontal, Space.s6)
        }
        .padding(.bottom, Space.s3)
    }

    @ViewBuilder
    private var categoryDetailCTA: some View {
        if let selectedId = selectedCategory,
           let c = categories.find(id: selectedId)
        {
            NavigationLink(value: NavRoute.categoryDetail(id: selectedId)) {
                HStack(spacing: Space.s2) {
                    Text(c.emoji)
                    Text("前往「\(c.nameZh)」主題頁")
                        .foregroundStyle(.tujiTeal)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .heavy))
                        .foregroundStyle(.tujiTeal)
                }
                .font(.system(size: 14, weight: .heavy))
                .padding(.horizontal, Space.s4)
                .padding(.vertical, Space.s3)
                .background(.tujiTealSoft, in: .rect(cornerRadius: Radius.md))
            }
            .buttonStyle(.plain)
            .padding(.horizontal, Space.s6)
            .padding(.bottom, Space.s3)
        }
    }

    @ViewBuilder
    private var content: some View {
        if self.store.loading, self.store.words.isEmpty {
            VStack {
                Spacer()
                ProgressView().tint(.tujiTeal)
                Text("載入中…")
                    .font(.tujiCaption)
                    .foregroundStyle(.tujiInk3)
                    .padding(.top, Space.s3)
                Spacer()
            }
            .frame(maxWidth: .infinity)
        } else if let error = store.lastError, self.store.words.isEmpty {
            VStack(spacing: Space.s3) {
                Mascot(pose: .think, size: 80)
                Text("載不到單字")
                    .font(.tujiH3)
                    .foregroundStyle(.tujiInk)
                Text(error.localizedDescription)
                    .font(.tujiCaption)
                    .foregroundStyle(.tujiInk3)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, Space.s6)
                BBtn(title: "重試", fullWidth: false, action: { Task { await self.store.reload() } })
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVGrid(
                    columns: [
                        GridItem(.flexible(), spacing: Space.s3),
                        GridItem(.flexible(), spacing: Space.s3)
                    ],
                    spacing: Space.s3
                ) {
                    ForEach(self.visibleWords) { word in
                        NavigationLink(value: NavRoute.wordDetail(id: word.id)) {
                            WordTile(word: word)
                        }
                        .buttonStyle(.plain)
                        .onLongPressGesture(minimumDuration: 0.35) {
                            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                            self.peekWord = word
                        }
                    }
                }
                .padding(.horizontal, Space.s6)

                if self.canShowMore {
                    Button {
                        self.visibleCount += self.pageSize
                    } label: {
                        Text("顯示更多")
                            .font(.system(size: 14, weight: .heavy))
                            .foregroundStyle(.tujiInk3)
                            .padding(.vertical, Space.s4)
                    }
                    .padding(.top, Space.s4)
                } else if self.filtered.isEmpty {
                    Text("這個分類還沒有字")
                        .font(.tujiBody)
                        .foregroundStyle(.tujiInk3)
                        .padding(.top, Space.s12)
                }
            }
        }
    }

    private func chip(label: String, value: String?) -> some View {
        let selected = self.selectedCategory == value
        return Button {
            self.selectedCategory = value
            self.visibleCount = self.pageSize
        } label: {
            Text(label)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(selected ? .white : .tujiInk2)
                .padding(.horizontal, Space.s4)
                .padding(.vertical, Space.s2)
                .background(
                    selected ? .tujiInk : .tujiCard,
                    in: .capsule
                )
                .overlay(
                    Capsule().stroke(.tujiInk4.opacity(selected ? 0 : 0.3), lineWidth: 1)
                )
        }
    }

    /// Categories that have at least one word in the dataset. Falls back to
    /// WordsStore-derived ids if CategoriesStore is still loading.
    private var chipCategories: [TujiCategory] {
        let presentIds = Set(self.store.categories)
        let known = self.categories.categories.filter { presentIds.contains($0.id) }
        if known.isEmpty {
            // Fallback: synthesize bare metadata from word-derived ids
            return self.store.categories.map {
                TujiCategory(id: $0, name: $0, nameZh: $0, emoji: "📚", description: nil, color: nil, imageUrl: nil)
            }
        }
        return known
    }

    private var filtered: [CardWord] {
        self.store.byCategory(self.selectedCategory)
    }

    private var visibleWords: [CardWord] {
        Array(self.filtered.prefix(self.visibleCount))
    }

    private var canShowMore: Bool {
        self.visibleCount < self.filtered.count
    }
}

#Preview {
    NavigationStack {
        CardsListView()
            .environment(WordsStore.shared)
            .environment(CategoriesStore.shared)
    }
}
