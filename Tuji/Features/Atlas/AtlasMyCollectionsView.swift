// 作者端「我的合集」：列出自己的合集 + 建立，並在編輯頁更換公開頭像、挑選成員、送審。
//
// 成員是作者自己已確認的圖鑑——公開、審核中、私人的都能加，被拒絕與下架的不行
// （後端 `eligible` 強制）；合集背景圖不再顯示，合集頭像照片則用於列表與詳情。
// 送審只審標題 + 簡介的文字，成員的圖各自過圖片閘。
//
// 建立合集的 sheet 搬到 AtlasCollectionCreateSheet.swift：作者主頁也有入口了。

import Nuke
import NukeUI
import SwiftUI

// MARK: - 我的合集列表

struct AtlasMyCollectionsView: View {
    @Environment(\.targetLanguage) private var currentLanguage
    @Environment(CommunityFeedRefresh.self) private var feedRefresh

    @State private var vm = MyCollectionsVM()

    @Binding var showCreate: Bool

    private var visibleCollections: [AtlasMyCollection] {
        self.vm.collections(for: self.currentLanguage)
    }

    /// A `LocalizedStringKey` rather than a resolved `String`: it is handed to a
    /// `Text` inside this view, whose environment locale already follows uiLang.
    private var emptyTitle: LocalizedStringKey {
        switch self.currentLanguage {
        case .ja: "目前沒有日文合集"
        case .en: "目前沒有英文合集"
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                if self.vm.showsPlaceholder {
                    TujiSkeletonRows(count: 3, height: 88)
                        .padding(.top, Space.s3)
                } else if self.visibleCollections.isEmpty {
                    self.emptyState
                        .padding(.top, Space.s5)
                } else {
                    ForEach(Array(self.visibleCollections.enumerated()), id: \.element.id) { index, collection in
                        if index > 0 {
                            Rectangle()
                                .fill(.tujiRule)
                                .frame(height: Border.bw1)
                                .padding(.horizontal, Space.s4)
                        }
                        NavigationLink {
                            // Kept even though `.task` re-runs on pop: that is
                            // SwiftUI's teardown behaviour, not a contract. The VM
                            // coalesces whichever of the two arrives second — and
                            // it is also how a 合集 deleted in there leaves this
                            // list.
                            AtlasCollectionEditView(collectionId: collection.id)
                                .onDisappear { Task { await self.vm.load() } }
                        } label: {
                            AtlasMyCollectionRow(collection: collection)
                                .padding(.horizontal, Space.s4)
                                .padding(.vertical, Space.s3)
                        }
                        .tujiRowStyle()
                    }
                }
            }
            .padding(.bottom, Space.s6)
        }
        .background(.tujiPaper)
        .task { await self.vm.load() }
        .refreshable { await self.vm.load() }
        .sheet(isPresented: self.$showCreate) {
            AtlasCollectionCreateSheet(language: self.currentLanguage) { collection in
                self.vm.prepend(collection)
            }
        }
    }

    private var emptyState: some View {
        TujiBlankState(
            icon: "square.stack.3d.up",
            emptyText: self.emptyTitle,
            error: self.vm.loadError,
            retry: { await self.vm.load() }
        )
    }
}

private struct AtlasMyCollectionRow: View {
    let collection: AtlasMyCollection

    var body: some View {
        HStack(spacing: Space.s3) {
            CollectionIdentityTile(
                collectionID: self.collection.id,
                avatarColor: self.collection.avatarColor,
                avatarImageURL: self.collection.avatarURL,
                size: 56
            )

            VStack(alignment: .leading, spacing: 4) {
                Text(self.collection.title)
                    .font(.tujiH3)
                    .foregroundStyle(.tujiInk)
                    .lineLimit(1)
                Text(tujiLocalized("\(self.collection.itemCount) 張卡片"))
                    .font(.tujiLabel)
                    .tracking(0.5)
                    .foregroundStyle(.tujiInk3)
            }
            Spacer(minLength: Space.s2)
            TujiStatusLabel(status: self.collection.review)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - 成員挑選

struct AtlasCollectionItemPicker: View {
    /// nil when the server took the item, otherwise the sentence to show
    /// (`CollectionEditVM.addMember`).
    let onAdd: (String) async -> String?

    @State private var model: CollectionCandidatesModel

    init(
        language: TargetLanguage,
        collectionReview: AtlasReviewStatus,
        existingIds: Set<String>,
        repo: CollectionManaging = LiveAtlasRepository.shared,
        onAdd: @escaping (String) async -> String?
    ) {
        _model = State(initialValue: CollectionCandidatesModel(
            language: language,
            collectionReview: collectionReview,
            existingIds: existingIds,
            repo: repo
        ))
        self.onAdd = onAdd
    }

    var body: some View {
        // No 完成 button: every tap adds its item immediately, so there was never
        // anything for 完成 to confirm — it only ever meant 關閉.
        TujiFormSheet(title: "加入卡片") {
            ScrollView {
                Group {
                    if self.model.loading {
                        TujiPageLoading()
                    } else if self.model.available.isEmpty {
                        TujiBlankState(
                            icon: "photo.on.rectangle.angled",
                            iconSize: 36,
                            emptyText: "沒有可加入的卡片。完成辨識與確認後，就能直接加入合集。",
                            error: self.model.loadError
                        )
                    } else {
                        VStack(spacing: Space.s3) {
                            if let addError = self.model.addError {
                                Text(addError)
                                    .font(.tujiLabel)
                                    .foregroundStyle(.tujiAlert)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            // Said once, above the grid, rather than on each
                            // tile: it is one fact about the 合集, not a
                            // property of eight photos.
                            if self.model.submitsMembersOnTheirOwn {
                                Text("未公開的卡片加入後會自動送審，通過才會出現在合集裡。")
                                    .font(.tujiLabel)
                                    .foregroundStyle(.tujiInk3)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            LazyVGrid(
                                columns: Array(repeating: GridItem(.flexible(), spacing: Space.s3), count: 3),
                                spacing: Space.s3
                            ) {
                                ForEach(self.model.available) { item in
                                    self.cell(item)
                                }
                            }
                        }
                        .padding(Space.s3)
                    }
                }
                // Without this the ScrollView shrinks to the spinner's width and
                // .tujiPaper only paints a strip down the middle of the sheet.
                .frame(maxWidth: .infinity)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .task { await self.model.load() }
        }
    }

    private func cell(_ item: AtlasPublicItem) -> some View {
        let isAdded = self.model.isAdded(item.id)
        let entersReview = self.model.entersReviewOnAdd(item)
        return Button {
            Task { await self.model.add(item.id, using: self.onAdd) }
        } label: {
            VStack(spacing: 2) {
                // The container owns the box. `.frame(height:)` alone leaves the
                // width to the photograph, and a wide one (the atlas serves
                // 320×135 crops) then drags the whole cell out of its grid
                // column — see AtlasPublicTile.
                Color.tujiPaper
                    .frame(height: 84)
                    .overlay {
                        LazyImage(url: item.imageURL) { state in
                            if let image = state.image {
                                image.resizable().aspectRatio(contentMode: .fill)
                            } else {
                                Image(systemName: "photo").foregroundStyle(.tujiInk3)
                            }
                        }
                        .pipeline(.shared)
                    }
                    .clipped()
                    .clipShape(RoundedRectangle(cornerRadius: Radius.r0))
                    .overlay(alignment: .bottomLeading) {
                        if let label = self.badge(for: item, entersReview: entersReview) {
                            Text(label)
                                .font(.tujiLabel)
                                .foregroundStyle(.white)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 3)
                                .background(.black.opacity(0.65), in: .rect(cornerRadius: Radius.r0))
                                .padding(4)
                        }
                    }
                    .overlay(alignment: .topTrailing) {
                        Image(systemName: isAdded ? "checkmark.circle.fill" : "plus.circle.fill")
                            .font(.tujiIcon(18))
                            .foregroundStyle(.white, isAdded ? .tujiAccumulation : .black.opacity(0.5))
                            .padding(4)
                    }
                Text(item.lemma)
                    .font(.tujiLabel)
                    .foregroundStyle(.tujiInk2)
                    .lineLimit(1)
            }
            .opacity(isAdded ? 0.6 : 1)
        }
        .buttonStyle(.plain)
        .disabled(isAdded)
        .accessibilityHint(entersReview ? Text("加入後會自動送審") : Text(verbatim: ""))
    }

    /// What adding this tile would do, which is not the same sentence in both
    /// 合集 states. 「將隨合集送審」 is true only while the 合集 can still carry
    /// a member through review; once it is live, the item goes on its own.
    private func badge(for item: AtlasPublicItem, entersReview: Bool) -> String? {
        if entersReview { return tujiLocalized("加入後送審") }
        return item.collectionPublicationLabel
    }
}
