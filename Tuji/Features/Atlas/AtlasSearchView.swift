// 物見搜尋 — find a 合集 by its title or author, or a word in everyone's cards.
//
// The model is `AtlasSearchModel`. Results follow the learning direction like
// the browse feed: a Japanese learner searching 「貓」 finds the 猫 people
// photographed, not the English "cat" cards.
//
// The field is drawn the way 搜尋's is (`SearchView`) — a `tujiPaper2` block
// with a 瞳黃 edge while focused — so the two searches read as one control.

import SwiftUI

struct AtlasSearchView: View {
    @Environment(\.targetLanguage) private var targetLanguage
    @Environment(TabNavigator.self) private var navigator
    @Environment(StudyFocus.self) private var studyFocus
    @Environment(BlockStore.self) private var blocks
    @Environment(\.dismiss) private var dismiss

    @State private var model = AtlasSearchModel()
    @FocusState private var fieldFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            self.searchBar
            self.content
            Spacer(minLength: 0)
        }
        .background(.tujiPaper)
        .navigationTitle("搜尋物見")
        .toolbar(.hidden, for: .navigationBar)
        // Same as 搜尋: the study-focus flag hides the tab bar while searching.
        .onAppear {
            self.studyFocus.enter()
            if self.model.query.isEmpty { self.fieldFocused = true }
        }
        .onDisappear { self.studyFocus.exit() }
        .task {
            await self.blocks.loadIfNeeded()
            self.model.applyBlocks(self.blocks.handles)
        }
        .onChange(of: self.blocks.handles) { _, handles in
            self.model.applyBlocks(handles)
        }
        .onChange(of: self.targetLanguage) { _, language in
            self.model.retry(language: language)
        }
    }

    // MARK: - Field

    private var searchBar: some View {
        HStack(spacing: Space.s3) {
            HStack(spacing: Space.s2) {
                Image(systemName: "magnifyingglass")
                    .font(.tujiIcon(17, weight: .semibold))
                    .foregroundStyle(.tujiInk2)
                TextField(
                    "搜尋合集、作者或單字",
                    text: Binding(
                        get: { self.model.query },
                        set: { self.model.updateQuery($0, language: self.targetLanguage) }
                    )
                )
                .focused(self.$fieldFocused)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .font(.tujiBody)
                .foregroundStyle(.tujiInk)
                .tint(.tujiInk)
                if !self.model.query.isEmpty {
                    Button {
                        self.model.updateQuery("", language: self.targetLanguage)
                        self.fieldFocused = true
                    } label: {
                        Image(systemName: "xmark")
                            .font(.tujiIcon(14, weight: .bold))
                            .foregroundStyle(.tujiInk2)
                            .frame(width: 44, height: 44)
                            .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text("清除"))
                }
            }
            .padding(.leading, Space.s3)
            .padding(.trailing, Space.s1)
            .frame(height: 52)
            .background(.tujiPaper2)
            .overlay {
                if self.fieldFocused {
                    Rectangle().stroke(.tujiCurrent, lineWidth: Border.bw2)
                }
            }
            .animation(Motion.ease(Motion.d1), value: self.fieldFocused)

            TujiNavTextAction(title: "取消") { self.dismiss() }
        }
        .padding(.horizontal, Space.s4)
        .padding(.vertical, Space.s2)
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        switch self.model.phase {
        case .idle:
            MascotEmptyState(
                pose: .sleep,
                title: "在大家的物見裡找找",
                message: "輸入合集名稱、作者，或想看的單字"
            )
            .tujiEmptyStatePlacement()
        case .loading where self.model.isEmpty:
            TujiSkeletonRows(count: 3, height: 80)
                .padding(.top, Space.s2)
        case let .failed(message):
            VStack {
                Spacer(minLength: Space.s5)
                TujiErrorState(title: "搜尋失敗", message: message) {
                    BBtn(title: "重試", fullWidth: false, action: {
                        self.model.retry(language: self.targetLanguage)
                    })
                }
                Spacer(minLength: Space.s5)
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, Space.s4)
        case .ready where self.model.isEmpty:
            MascotEmptyState(
                pose: .sleep,
                title: "找不到「\(self.model.lastQuery)」",
                message: "換個關鍵字，或用中文試試"
            )
            .tujiEmptyStatePlacement()
        case .loading, .ready:
            self.results
        }
    }

    private var results: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                if !self.model.collections.isEmpty {
                    self.sectionHeader("合集", count: self.model.collections.count)
                    ForEach(Array(self.model.collections.enumerated()), id: \.element.id) { index, collection in
                        if index > 0 {
                            Rectangle()
                                .fill(.tujiRule)
                                .frame(height: Border.bw1)
                                .padding(.horizontal, Space.s4)
                        }
                        AtlasCollectionCard(collection: collection) {
                            self.navigator.push(
                                .atlasCollectionDetail(slug: collection.slug, preview: collection)
                            )
                        }
                    }
                }

                if !self.model.items.isEmpty {
                    self.sectionHeader("單字卡片", count: self.model.items.count)
                        .padding(.top, self.model.collections.isEmpty ? 0 : Space.s4)
                    LazyVGrid(
                        columns: [
                            GridItem(.flexible(), spacing: Space.s3, alignment: .top),
                            GridItem(.flexible(), spacing: Space.s3, alignment: .top)
                        ],
                        spacing: Space.s3
                    ) {
                        ForEach(self.model.items) { item in
                            AtlasPublicTile(
                                item: item,
                                onOpen: { self.navigator.push(.atlasPublicItem(item: item)) },
                                onOpenAuthor: item.author.map { author in
                                    { self.navigator.push(.authorProfile(handle: author.handle, isSelf: false)) }
                                }
                            )
                        }
                    }
                    .padding(.horizontal, Space.s4)
                }
            }
            .padding(.top, Space.s2)
            .padding(.bottom, Space.s5)
        }
        .scrollDismissesKeyboard(.immediately)
    }

    private func sectionHeader(_ title: LocalizedStringKey, count: Int) -> some View {
        HStack(spacing: Space.s2) {
            // Section labels are 墨3, like 搜尋's 「最近搜尋」.
            Text(title)
                .font(.tujiLabel)
                .tracking(0.5)
                .foregroundStyle(.tujiInk3)
            Text("\(count)")
                .font(.tujiLabel)
                .foregroundStyle(.tujiInk3)
            if self.model.phase == .loading {
                TujiProgressBar(progress: nil).frame(width: 40)
            }
        }
        .padding(.horizontal, Space.s4)
        .padding(.bottom, Space.s2)
    }
}
