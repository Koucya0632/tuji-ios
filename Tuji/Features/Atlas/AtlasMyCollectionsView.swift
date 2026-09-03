// 作者端「我的合集」：列出自己的合集 + 建立，並在編輯頁更換公開頭像、挑選成員、送審。
//
// 成員只能來自作者自己「已通過」的公開項目（後端強制）；合集背景圖不再顯示，
// 合集頭像照片則用於列表與詳情。送審只審標題 + 簡介的文字。

import Nuke
import NukeUI
import SwiftUI

// MARK: - 我的合集列表

struct AtlasMyCollectionsView: View {
    @Environment(\.targetLanguage) private var currentLanguage
    @Environment(CommunityFeedRefresh.self) private var feedRefresh

    @State private var vm = MyCollectionsVM()
    @State private var pendingDelete: AtlasMyCollection?

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
        let target = self.pendingDelete
        return ScrollView {
            VStack(spacing: 0) {
                if let deleteError = self.vm.deleteError {
                    Text(deleteError)
                        .font(.tujiBodySm)
                        .foregroundStyle(.tujiAlert)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, Space.s4)
                        .padding(.vertical, Space.s3)
                }
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
                        TujiSwipeRow(
                            actionLabel: "刪除",
                            systemImage: "trash",
                            action: { self.pendingDelete = collection }
                        ) {
                            NavigationLink {
                                // Kept even though `.task` re-runs on pop: that is
                                // SwiftUI's teardown behaviour, not a contract. The VM
                                // coalesces whichever of the two arrives second.
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
        .tujiPrompt(
            isPresented: Binding(
                get: { self.pendingDelete != nil },
                set: { if !$0 { self.pendingDelete = nil } }
            ),
            style: .destructive,
            title: "刪除這個合集？",
            message: LocalizedStringKey(target.map(self.deleteMessage) ?? ""),
            primary: TujiPromptAction("刪除", role: .destructive) {
                if let target {
                    Task { await self.delete(target) }
                }
            },
            secondary: TujiPromptAction("取消", role: .cancel) {}
        )
        .tujiStatusToast(isPresented: self.vm.deleting, style: .deleting)
    }

    private var emptyState: some View {
        TujiBlankState(
            icon: "square.stack.3d.up",
            emptyText: self.emptyTitle,
            error: self.vm.loadError,
            retry: { await self.vm.load() }
        )
    }

    /// The words for whichever warning the VM says is true. Which one that is
    /// is the module's answer; this is only the sentence.
    private func deleteMessage(for collection: AtlasMyCollection) -> String {
        switch self.vm.deleteWarning(for: collection) {
        case .cancelsReview:
            tujiLocalized("這會取消送審並刪除合集，原始圖鑑卡片不受影響。")
        case .takesDownFromPublic:
            tujiLocalized("這會立即將合集從物見下架並刪除，原始圖鑑卡片不受影響。")
        case .privateOnly:
            tujiLocalized("這個合集會被永久刪除，原始圖鑑卡片不受影響。")
        }
    }

    /// The View's only job here is to hand over the environment's feed signal;
    /// what a deletion refreshes is `AtlasMutationRefresh`'s call.
    ///
    /// No `pendingDelete = nil` afterwards: `TujiPrompt` sets `isPresented`
    /// false *before* running the action, which fires the binding's setter and
    /// clears it — so the line was already a no-op by the time the await
    /// returned.
    private func delete(_ collection: AtlasMyCollection) async {
        await self.vm.delete(
            collection,
            refreshing: LiveAtlasMutationRefresher(feed: self.feedRefresh)
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
                Text(tujiLocalized("\(self.collection.itemCount) 字"))
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

// MARK: - 建立合集

private struct AtlasCollectionCreateSheet: View {
    let onCreated: (AtlasMyCollection) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var model: CollectionCreateModel

    init(
        language: TargetLanguage,
        repo: CollectionManaging = LiveAtlasRepository.shared,
        onCreated: @escaping (AtlasMyCollection) -> Void
    ) {
        _model = State(initialValue: CollectionCreateModel(language: language, repo: repo))
        self.onCreated = onCreated
    }

    var body: some View {
        TujiSheetShell(title: "建立合集") {
            ScrollView {
                VStack(alignment: .leading, spacing: Space.s5) {
                    TujiField(label: "標題") {
                        TujiTextField(placeholder: "例如：生活日常", text: self.$model.title)
                    }
                    TujiField(
                        label: "簡介（選填）",
                        footer: "合集可直接加入這個語言中已確認完成的圖鑑；公開合集時會一起送審。"
                    ) {
                        TujiTextField(
                            placeholder: "簡單描述這個合集",
                            text: self.$model.description,
                            lineLimit: 2...4,
                            errorMessage: self.model.errorMessage
                        )
                    }
                    TujiField(label: "語言") {
                        Text(self.model.language == .ja ? "日文" : "英文")
                            .font(.tujiBody)
                            .foregroundStyle(.tujiInk2)
                    }

                    BBtn(
                        title: self.model.creating ? "建立中…" : "建立",
                        fullWidth: true
                    ) {
                        Task {
                            guard let collection = await self.model.create() else { return }
                            self.onCreated(collection)
                            self.dismiss()
                        }
                    }
                    .disabled(!self.model.canCreate)
                    .padding(.horizontal, Space.s4)
                }
                .padding(.top, Space.s4)
                .padding(.bottom, Space.s6)
            }
        }
    }
}

// MARK: - 成員挑選

struct AtlasCollectionItemPicker: View {
    let onAdd: (String) async -> Bool

    @State private var model: CollectionCandidatesModel

    init(
        language: TargetLanguage,
        existingIds: Set<String>,
        repo: CollectionManaging = LiveAtlasRepository.shared,
        onAdd: @escaping (String) async -> Bool
    ) {
        _model = State(initialValue: CollectionCandidatesModel(
            language: language,
            existingIds: existingIds,
            repo: repo
        ))
        self.onAdd = onAdd
    }

    var body: some View {
        // No 完成 button: every tap adds its item immediately, so there was never
        // anything for 完成 to confirm — it only ever meant 關閉.
        TujiFormSheet(title: "加入項目") {
            ScrollView {
                Group {
                    if self.model.loading {
                        TujiPageLoading()
                    } else if self.model.available.isEmpty {
                        TujiBlankState(
                            icon: "photo.on.rectangle.angled",
                            iconSize: 36,
                            emptyText: "沒有可加入的項目。完成辨識與確認後，就能直接加入合集。",
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
        return Button {
            Task { await self.model.add(item.id, using: self.onAdd) }
        } label: {
            VStack(spacing: 2) {
                ZStack {
                    Rectangle().fill(.tujiPaper)
                    LazyImage(url: item.imageURL) { state in
                        if let image = state.image {
                            image.resizable().aspectRatio(contentMode: .fill)
                        } else {
                            Image(systemName: "photo").foregroundStyle(.tujiInk3)
                        }
                    }
                    .pipeline(.shared)
                }
                .frame(height: 84)
                .clipped()
                .clipShape(RoundedRectangle(cornerRadius: Radius.r0))
                .overlay(alignment: .bottomLeading) {
                    if let label = item.collectionPublicationLabel {
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
                        .foregroundStyle(isAdded ? .white : .white, isAdded ? .tujiAccumulation : .black.opacity(0.5))
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
    }
}
