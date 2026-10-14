// 情境故事 — choosing the 圖鑑物品, laid out the way the 圖鑑 tab is.
//
// It used to be a flat list of every candidate: 757 official words in a row,
// a 44pt thumbnail each, under the person's own cards. Picking a word for a
// story is browsing the 圖鑑, so it now looks like it: the source chips,
// 官方 as the shelf of theme covers, and a theme's words as the same two
// columns of `WordTile`s — tapping one picks it instead of opening it.
//
// 已收進 is not a chip: those are someone else's 物見 cards, the server refuses
// them, and `StoryBuilderModel.candidates` already leaves them out.

import SwiftUI

struct StoryItemPicker: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(CategoriesStore.self) private var categories
    @Environment(ProgressStore.self) private var progress
    @Environment(MasteryStore.self) private var mastery
    @Environment(LocalCache.self) private var cache

    let model: StoryBuilderModel
    @State private var query = ""
    @State private var source: CardsSource = .official
    @State private var path: [TujiCategory] = []

    static let sources: [CardsSource] = [.official, .mine, .bookmarked]

    var body: some View {
        VStack(spacing: 0) {
            self.header
            NavigationStack(path: self.$path) {
                self.root
                    .toolbar(.hidden, for: .navigationBar)
                    .navigationDestination(for: TujiCategory.self) { category in
                        self.themePage(category)
                    }
            }
        }
        .background(Color.tujiPaper.ignoresSafeArea())
        .presentationDetents([.large])
        .warmsAccumulation(.themeIndex)
    }

    // MARK: - Bits

    private var header: some View {
        HStack {
            Text(verbatim: tujiLocalized("已選 \(self.model.picked.count)/\(StoryBuilderModel.maxItems)"))
                .font(.tujiBodySm)
                .foregroundStyle(.tujiInk3)
            Spacer()
            Button {
                self.dismiss()
            } label: {
                Text("完成")
                    .font(.tujiBody(.strong))
                    .foregroundStyle(.tujiInk)
                    .frame(minHeight: 44)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, Space.s4)
        .padding(.top, Space.s2)
    }

    private var root: some View {
        VStack(spacing: 0) {
            TextField("搜尋單字", text: self.$query)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .font(.tujiBody)
                .foregroundStyle(.tujiInk)
                .tint(.tujiInk)
                .padding(.horizontal, Space.s3)
                .frame(height: 48)
                .background(.tujiPaper2)
                .padding(.horizontal, Space.s4)
                .padding(.vertical, Space.s2)

            let trimmed = self.query.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                self.chipRow
                if self.source.showsThemes {
                    self.themeShelf
                } else {
                    self.wordGrid(self.sourceWords)
                }
            } else {
                self.wordGrid(SearchVM.localMatches(trimmed, in: self.model.candidates))
            }
        }
        .background(Color.tujiPaper.ignoresSafeArea())
    }

    /// Same chip as the 圖鑑 tab's: one source is always in effect.
    private var chipRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Space.s2) {
                ForEach(Self.sources) { value in
                    let selected = self.source == value
                    Button {
                        self.source = value
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
            }
            .padding(.horizontal, Space.s4)
        }
        .padding(.bottom, Space.s3)
    }

    /// 官方: the themes, each with its cover. No padlock — a story is not
    /// study, and nothing about writing one is locked by membership.
    private var themeShelf: some View {
        ScrollView {
            LazyVGrid(columns: CardsListView.gridColumns, spacing: Space.s2) {
                ForEach(self.themes) { category in
                    let words = self.words(in: category.id)
                    NavigationLink(value: category) {
                        CategoryCoverTile(
                            category: category,
                            wordCount: words.count,
                            status: ThemeStatus.of(
                                words: words,
                                masteryScore: { self.mastery.score(for: $0) },
                                progress: self.progress.categoryProgress,
                                categoryId: category.id
                            )
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, Space.s4)
            .padding(.bottom, Space.s4)
        }
        .scrollDismissesKeyboard(.interactively)
    }

    private func themePage(_ category: TujiCategory) -> some View {
        self.wordGrid(self.words(in: category.id))
            .padding(.top, Space.s2)
            .background(Color.tujiPaper.ignoresSafeArea())
            .navigationTitle(category.nameZh)
            .navigationBarTitleDisplayMode(.inline)
    }

    private func wordGrid(_ words: [CardWord]) -> some View {
        ScrollView {
            if words.isEmpty {
                self.emptyState
            } else {
                LazyVGrid(columns: CardsListView.gridColumns, spacing: Space.s4) {
                    ForEach(words) { word in
                        self.tile(word)
                    }
                }
                .padding(.horizontal, Space.s4)
                .padding(.bottom, Space.s4)
            }
        }
        .scrollDismissesKeyboard(.interactively)
    }

    @ViewBuilder
    private var emptyState: some View {
        if !self.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            Text("找不到這個單字")
                .font(.tujiBodySm)
                .foregroundStyle(.tujiInk3)
                .padding(.vertical, Space.s4)
        } else {
            switch self.source {
            case .mine:
                MascotEmptyState(pose: .sleep, title: "還沒有自製圖鑑", message: "用底下中間的相機拍一張，就會多一張卡片")
                    .tujiEmptyStatePlacement()
                    .frame(minHeight: 320)
            case .bookmarked:
                MascotEmptyState(pose: .sleep, title: "還沒有書籤", message: "你加書籤的字會出現在這裡")
                    .tujiEmptyStatePlacement()
                    .frame(minHeight: 320)
            case .official, .taken:
                EmptyView()
            }
        }
    }

    /// A 圖鑑 tile that picks instead of opening. The check sits top-left —
    /// top-right is `WordTile`'s source dot.
    private func tile(_ word: CardWord) -> some View {
        let picked = self.model.isPicked(word)
        let blocked = !picked && !self.model.canPickMore
        return Button {
            self.model.toggle(word)
        } label: {
            WordTile(word: word)
                .overlay(alignment: .topLeading) {
                    Image(systemName: picked ? "checkmark.square.fill" : "square")
                        .font(.tujiIcon(20))
                        .foregroundStyle(picked ? Color.tujiInk : .tujiInk3)
                        .background(Color.tujiPaper, in: .rect(cornerRadius: 3))
                        .padding(Space.s2)
                }
                .overlay {
                    if picked {
                        Rectangle()
                            .stroke(Color.tujiInk, lineWidth: Border.bw3)
                            // Outside the tile, so the frame does not sit on
                            // the word under the picture.
                            .padding(-Space.s1)
                    }
                }
                .contentShape(.rect)
                .opacity(blocked ? 0.4 : 1)
        }
        .buttonStyle(.plain)
        .disabled(blocked)
        .accessibilityAddTraits(picked ? .isSelected : [])
    }

    // MARK: - Data

    private var themes: [TujiCategory] {
        ThemeCatalog.themes(
            from: self.categories.categories,
            presentIds: Set(self.model.candidates.map(\.category))
        )
    }

    private func words(in categoryId: String) -> [CardWord] {
        self.model.candidates.filter { $0.category == categoryId }
    }

    private var sourceWords: [CardWord] {
        self.model.candidates.filter {
            self.source.matches($0, isBookmarked: self.cache.isFavorite)
        }
    }
}
