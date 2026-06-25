// Favorites surface (§III.K). Reads LocalCache.favoriteIds × WordsStore
// — no dedicated /api/users/favorites GET round trip; LocalCache is the
// single source of truth, kept in sync by WordsStore + AuthService's
// catch-up on sign-in.
//
// UX rules per design book:
//   tap cell        → WordPeekSheet  (NOT push WordDetail)
//   long-press      → contextMenu 「移除收藏」
//   chip filter     → only categories with at least one favorite show up

import OSLog
import SwiftUI

struct FavoritesView: View {
    enum Sort: String, CaseIterable, Hashable {
        case az, za, byCategory

        var label: LocalizedStringKey {
            switch self {
            case .az: "A → Z"
            case .za: "Z → A"
            case .byCategory: "依主題"
            }
        }
    }

    @Environment(LocalCache.self) private var cache
    @Environment(WordsStore.self) private var words
    @Environment(CategoriesStore.self) private var categories
    @Environment(AuthService.self) private var auth

    @State private var selectedCategory: String?
    @State private var sort: Sort = .az
    @State private var peekWord: CardWord?
    @State private var pushAfterDismiss: String?

    var body: some View {
        VStack(spacing: 0) {
            self.header
            self.content
        }
        .background(.tujiBg)
        .navigationTitle("我的收藏")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await self.words.loadIfNeeded()
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
        VStack(spacing: Space.s3) {
            if self.isGuest {
                self.guestBanner
            }
            if !self.allFavorites.isEmpty {
                self.chipRow
                self.toolbar
            }
        }
    }

    private var guestBanner: some View {
        HStack(spacing: Space.s2) {
            Image(systemName: "icloud.slash")
                .foregroundStyle(.tujiInk3)
            Text("訪客模式 · 收藏只存在這台裝置")
                .font(.tujiCaption)
                .foregroundStyle(.tujiInk2)
            Spacer()
        }
        .padding(.horizontal, Space.s4)
        .padding(.vertical, Space.s3)
        .background(.tujiTealSoft, in: .rect(cornerRadius: Radius.md))
        .padding(.horizontal, Space.s6)
        .padding(.top, Space.s3)
    }

    private var chipRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Space.s2) {
                self.chip(label: "全部", value: nil)
                ForEach(self.favoriteCategories, id: \.id) { c in
                    self.chip(label: c.nameZh, value: c.id)
                }
            }
            .padding(.horizontal, Space.s6)
        }
        .padding(.top, Space.s3)
    }

    private func chip(label: String, value: String?) -> some View {
        let selected = self.selectedCategory == value
        return Button {
            self.selectedCategory = value
        } label: {
            Text(label)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(selected ? .white : .tujiInk2)
                .padding(.horizontal, Space.s4)
                .padding(.vertical, Space.s2)
                .background(selected ? .tujiInk : .tujiCard, in: .capsule)
                .overlay(
                    Capsule().stroke(.tujiInk4.opacity(selected ? 0 : 0.3), lineWidth: 1)
                )
        }
    }

    private var toolbar: some View {
        HStack {
            Text("\(self.filtered.count) 個收藏")
                .font(.tujiOverline)
                .tracking(2)
                .foregroundStyle(.tujiInk3)
            Spacer()
            Menu {
                ForEach(Sort.allCases, id: \.self) { s in
                    Button {
                        self.sort = s
                    } label: {
                        if s == self.sort {
                            Label(s.label, systemImage: "checkmark")
                        } else {
                            Text(s.label)
                        }
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.up.arrow.down")
                    Text(self.sort.label)
                }
                .font(.system(size: 13, weight: .heavy))
                .foregroundStyle(.tujiTeal)
            }
        }
        .padding(.horizontal, Space.s6)
        .padding(.vertical, Space.s2)
    }

    @ViewBuilder
    private var content: some View {
        if self.allFavorites.isEmpty {
            self.emptyState
        } else {
            self.grid
        }
    }

    private var emptyState: some View {
        VStack {
            Spacer(minLength: Space.s8)
            MascotEmptyState(
                pose: .sleep,
                title: "還沒有收藏的單字",
                message: "在圖鑑或字卡頁按愛心，把喜歡的字存進來"
            ) {
                NavigationLink(value: NavRoute.cards) {
                    Text("去單字庫逛逛")
                        .font(.system(size: 15, weight: .heavy))
                        .foregroundStyle(.tujiInk)
                        .padding(.vertical, Space.s3)
                        .padding(.horizontal, Space.s6)
                        .background(.tujiYellow, in: .capsule)
                }
                .buttonStyle(.plain)
            }
            Spacer(minLength: Space.s8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, Space.s6)
    }

    private var grid: some View {
        ScrollView {
            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: Space.s3),
                    GridItem(.flexible(), spacing: Space.s3)
                ],
                spacing: Space.s3
            ) {
                ForEach(self.filtered) { word in
                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        self.peekWord = word
                    } label: {
                        WordTile(word: word)
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button(role: .destructive) {
                            self.cache.toggleFavorite(word.id)
                        } label: {
                            Label("移除收藏", systemImage: "heart.slash")
                        }
                    }
                }
            }
            .padding(.horizontal, Space.s6)
            .padding(.top, Space.s3)
            .padding(.bottom, Space.s8)
        }
    }

    // MARK: - Derived

    private var isGuest: Bool {
        if case .signedIn = auth.state { return false }
        return true
    }

    private var allFavorites: [CardWord] {
        self.words.byIds(self.cache.favoriteIds)
    }

    /// Categories that have at least one favorited word.
    private var favoriteCategories: [TujiCategory] {
        let presentIds = Set(self.allFavorites.map(\.category))
        return self.categories.categories.filter { presentIds.contains($0.id) }
    }

    private var filtered: [CardWord] {
        var list = self.allFavorites
        if let id = selectedCategory {
            list = list.filter { $0.category == id }
        }
        switch self.sort {
        case .az:
            list.sort { $0.word.localizedCompare($1.word) == .orderedAscending }
        case .za:
            list.sort { $0.word.localizedCompare($1.word) == .orderedDescending }
        case .byCategory:
            list.sort {
                if $0.category != $1.category { return $0.category < $1.category }
                return $0.word.localizedCompare($1.word) == .orderedAscending
            }
        }
        return list
    }
}

#Preview {
    NavigationStack {
        FavoritesView()
            .environment(LocalCache.shared)
            .environment(WordsStore.shared)
            .environment(CategoriesStore.shared)
            .environment(AuthService.shared)
    }
}
