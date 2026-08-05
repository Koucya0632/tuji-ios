// 2-column grid of every word, filterable by category chip.
//
// Chips show the localized zh name from CategoriesStore. Selecting a chip
// filters the grid in place without adding a separate category-page CTA.

import SwiftUI

struct CardsListView: View {
    @Environment(WordsStore.self) private var store
    @Environment(CategoriesStore.self) private var categories
    @Environment(MasteryStore.self) private var mastery

    @State private var selectedCategory: String?
    @State private var visibleCount: Int = 60
    @State private var peekWord: CardWord?
    @State private var pushAfterDismiss: String?
    @State private var showCapture = false

    private let pageSize: Int = 60

    var body: some View {
        VStack(spacing: 0) {
            self.header
            AtlasCaptureProgressStrip()
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
            await self.categories.loadIfNeeded()
            await self.mastery.loadIfNeeded()
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
        .fullScreenCover(isPresented: self.$showCapture) {
            AtlasCaptureView()
        }
    }

    // MARK: - Bits

    private var header: some View {
        HStack {
            Text("圖鑑")
                .font(.tujiH2)
                .foregroundStyle(.tujiInk)
            Spacer()
            Button {
                self.showCapture = true
            } label: {
                Image(systemName: "camera.viewfinder")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(.tujiInk2)
            }
            .buttonStyle(.plain)
            .tourAnchor(.capture)
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
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Space.s2) {
                self.chip(label: "全部", value: nil)
                ForEach(self.chipCategories, id: \.id) { c in
                    self.chip(label: c.nameZh, value: c.id)
                }
            }
            .padding(.horizontal, Space.s4)
        }
        .padding(.bottom, Space.s3)
    }

    @ViewBuilder
    private var content: some View {
        if self.store.loading, self.store.words.isEmpty {
            // Two-column skeleton in the shape of the grid that is coming —
            // the point of a skeleton over a spinner is that the layout does
            // not jump when the real tiles land.
            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: Space.s2),
                    GridItem(.flexible(), spacing: Space.s2)
                ],
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
            MascotEmptyState(
                pose: .think,
                title: "載不到單字",
                message: "\(error.localizedDescription)"
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
                    columns: [
                        GridItem(.flexible(), spacing: Space.s2),
                        GridItem(.flexible(), spacing: Space.s2)
                    ],
                    spacing: Space.s4
                ) {
                    ForEach(self.visibleWords) { word in
                        NavigationLink(value: NavRoute.wordDetail(id: word.id)) {
                            WordTile(
                                word: word,
                                showMastery: true,
                                masteryScore: self.mastery.score(for: word.id),
                                nextReviewDate: self.mastery.nextReviewDate(for: word.id)
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
                        self.visibleCount += self.pageSize
                    } label: {
                        Text("顯示更多")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.tujiInk3)
                            .padding(.vertical, Space.s3)
                    }
                    .padding(.top, Space.s3)
                } else if self.filtered.isEmpty {
                    Text("這個分類還沒有字")
                        .font(.tujiBodySm)
                        .foregroundStyle(.tujiInk3)
                        .padding(.top, Space.s5)
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
                .padding(.horizontal, Space.s3)
                .padding(.vertical, Space.s2)
                .background(
                    selected ? .tujiInk : .tujiPaper,
                    in: .rect(cornerRadius: Radius.r0)
                )
                .overlay(
                    Rectangle().stroke(.tujiRule.opacity(selected ? 0 : 0.3), lineWidth: 1)
                )
        }
    }

    /// Categories that have at least one word in the dataset. Falls back to
    /// WordsStore-derived ids if CategoriesStore is still loading.
    private var chipCategories: [TujiCategory] {
        let presentIds = Set(self.store.categories)
        let known = Self.visibleThemeCategories(
            from: self.categories.categories,
            presentIds: presentIds
        )
        if known.isEmpty {
            // Fallback: synthesize bare metadata from word-derived ids
            return self.store.categories.map {
                TujiCategory(id: $0, name: $0, nameZh: $0, emoji: "", description: nil, color: nil, imageUrl: nil)
            }
        }
        return known
    }

    static func visibleThemeCategories(
        from categories: [TujiCategory],
        presentIds: Set<String>
    )
        -> [TujiCategory]
    {
        categories.filter {
            presentIds.contains($0.id) || $0.id == "custom" || $0.id == "community"
        }
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
            .environment(MasteryStore.shared)
    }
}
