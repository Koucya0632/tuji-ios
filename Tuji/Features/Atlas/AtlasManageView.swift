// 自制圖鑑「管理」頁 (reached from 設定 → 自制圖鑑). List-based 查 + 刪 only:
// browse the cards you've made, open one for a read-only look, or delete it.
// Creating new cards lives in the camera quick-add flow (AtlasCaptureView);
// editing (改) is a future addition that needs a backend PATCH endpoint.
//
// The list is keyed on uploaded images and joined to their confirmed item (if
// any) for the answer/中文 labels; deleting an image cascades to its item +
// cards via AtlasStore.deleteImage.

import NukeUI
import SwiftUI

struct AtlasManageView: View {
    @State private var store = AtlasStore.shared
    @State private var pendingDelete: AtlasImageSummary?
    @State private var isSelecting = false
    @State private var selectedIds: Set<String> = []
    @State private var showBatchDeleteConfirm = false
    @State private var errorMessage: String?

    var body: some View {
        // Capture the pending rows before the prompt runs its action: tujiPrompt
        // sets isPresented = false first (which nils the backing state), so
        // reading it inside the action is always empty — the "刪除沒反應" bug.
        let target = self.pendingDelete
        let batch = Array(self.selectedIds)
        return List {
            Section("我的圖鑑卡片") {
                if let errorMessage {
                    Text(errorMessage)
                        .font(.tujiCaption)
                        .foregroundStyle(.tujiCoral)
                }
                if self.store.images.isEmpty {
                    self.emptyRow
                } else {
                    ForEach(self.store.images) { image in
                        self.imageRow(image)
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(.tujiBg)
        .navigationTitle("自制圖鑑")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if !self.store.images.isEmpty {
                    Button(self.isSelecting ? "完成" : "選取") {
                        self.isSelecting.toggle()
                        if !self.isSelecting { self.selectedIds.removeAll() }
                    }
                    .font(.system(size: 15, weight: .heavy))
                    .tint(.tujiTeal)
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            if self.isSelecting, !self.selectedIds.isEmpty {
                self.deleteBar
            }
        }
        .task { await self.store.sync(since: nil) }
        .tujiPrompt(
            isPresented: Binding(
                get: { self.pendingDelete != nil },
                set: { if !$0 { self.pendingDelete = nil } }
            ),
            style: .destructive,
            title: "刪除這張卡片？",
            message: "圖片與它生成的卡片都會一起刪除，無法復原。",
            primary: TujiPromptAction("刪除", role: .destructive) {
                if let target { Task { await self.delete([target.id]) } }
            },
            secondary: TujiPromptAction("取消", role: .cancel) {}
        )
        .tujiPrompt(
            isPresented: self.$showBatchDeleteConfirm,
            style: .destructive,
            title: "刪除所選卡片？",
            message: "圖片與它們生成的卡片都會一起刪除，無法復原。",
            primary: TujiPromptAction("刪除", role: .destructive) {
                Task { await self.delete(batch) }
            },
            secondary: TujiPromptAction("取消", role: .cancel) {}
        )
    }

    /// One card row. In selection mode it's a tappable checkbox row; otherwise
    /// it keeps the push-to-detail + swipe-to-delete behaviour.
    @ViewBuilder
    private func imageRow(_ image: AtlasImageSummary) -> some View {
        if self.isSelecting {
            let selected = self.selectedIds.contains(image.id)
            Button {
                self.toggleSelection(image.id)
            } label: {
                HStack(spacing: Space.s3) {
                    Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(selected ? .tujiTeal : .tujiInk4)
                    self.row(image)
                }
            }
            .buttonStyle(.plain)
        } else {
            NavigationLink {
                AtlasManageDetailView(image: image, onDelete: { self.pendingDelete = image })
            } label: {
                self.row(image)
            }
            .swipeActions(edge: .trailing) {
                Button(role: .destructive) {
                    self.pendingDelete = image
                } label: {
                    Label("刪除", systemImage: "trash")
                }
            }
        }
    }

    private var deleteBar: some View {
        BBtn(
            title: "刪除 \(self.selectedIds.count) 張卡片",
            bg: .tujiCoral,
            fg: .white,
            fullWidth: true,
            icon: "trash"
        ) {
            self.showBatchDeleteConfirm = true
        }
        .padding(.horizontal, Space.s6)
        .padding(.vertical, Space.s3)
        .background(.tujiBg)
    }

    private func toggleSelection(_ id: String) {
        if self.selectedIds.contains(id) {
            self.selectedIds.remove(id)
        } else {
            self.selectedIds.insert(id)
        }
    }

    private var emptyRow: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("還沒有自制圖鑑卡片")
                .font(.system(size: 15, weight: .heavy))
                .foregroundStyle(.tujiInk)
            Text("回圖鑑頁點右上角相機，拍一張就能做卡片。")
                .font(.tujiCaption)
                .foregroundStyle(.tujiInk3)
        }
        .padding(.vertical, Space.s2)
    }

    private func row(_ image: AtlasImageSummary) -> some View {
        let item = self.item(for: image)
        return HStack(spacing: Space.s3) {
            ZStack {
                Rectangle().fill(.tujiCard)
                LazyImage(url: image.thumbURL) { state in
                    if let img = state.image {
                        img.resizable().aspectRatio(contentMode: .fill)
                    } else if state.error != nil {
                        Image(systemName: "photo").foregroundStyle(.tujiInk4)
                    } else {
                        ProgressView().tint(.tujiTeal)
                    }
                }
            }
            .frame(width: 52, height: 52)
            .clipShape(RoundedRectangle(cornerRadius: Radius.md))

            VStack(alignment: .leading, spacing: 2) {
                Text(item?.lemma ?? tujiLocalized("未完成"))
                    .font(.system(size: 15, weight: .heavy))
                    .foregroundStyle(.tujiInk)
                    .lineLimit(1)
                if let zh = item?.displayZhHant, !zh.isEmpty {
                    Text(zh)
                        .font(.tujiCaption)
                        .foregroundStyle(.tujiInk3)
                        .lineLimit(1)
                }
            }
            Spacer()
            Text(image.status)
                .font(.system(size: 11, weight: .heavy))
                .foregroundStyle(.tujiInk4)
        }
        .padding(.vertical, 2)
    }

    private func item(for image: AtlasImageSummary) -> AtlasItem? {
        self.store.items.first { $0.imageId == image.id }
    }

    private func delete(_ ids: [String]) async {
        guard !ids.isEmpty else { return }
        self.errorMessage = nil
        do {
            // AtlasStore.deleteImage already updates the atlas list state.
            // Don't invalidate() the main stores here — clearing
            // WordsStore.loaded trips RootView's splash gate and bounces the
            // app back to Splash. Refresh the home counters in place instead.
            for id in ids {
                try await self.store.deleteImage(id: id)
            }
            // Atlas cards show in the 圖鑑 grid as custom words — reload so the
            // deleted ones disappear there too. reload() not invalidate().
            async let words: Void = WordsStore.shared.reload()
            async let progress: Void = ProgressStore.shared.reload()
            async let stats: Void = StudyStatsStore.shared.reload()
            _ = await (words, progress, stats)
        } catch {
            self.errorMessage = error.localizedDescription
        }
        self.pendingDelete = nil
        self.selectedIds.removeAll()
        self.isSelecting = false
    }
}

// MARK: - Read-only detail

private struct AtlasManageDetailView: View {
    let image: AtlasImageSummary
    let onDelete: () -> Void

    @State private var store = AtlasStore.shared
    @Environment(\.dismiss) private var dismiss

    private var item: AtlasItem? {
        self.store.items.first { $0.imageId == self.image.id }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.s4) {
                ZStack {
                    Rectangle().fill(.tujiCard)
                    LazyImage(url: self.image.imageURL) { state in
                        if let img = state.image {
                            img.resizable().aspectRatio(contentMode: .fit)
                        } else if state.error != nil {
                            Image(systemName: "photo")
                                .font(.system(size: 28, weight: .bold))
                                .foregroundStyle(.tujiInk4)
                        } else {
                            ProgressView().tint(.tujiTeal)
                        }
                    }
                }
                .frame(height: 260)
                .clipShape(RoundedRectangle(cornerRadius: Radius.lg))

                if let item {
                    self.detailRow("圖片名稱", item.lemma)
                    self.detailRow("中文名稱", item.displayZhHant)
                    if let fine = item.fineLabel, !fine.isEmpty { self.detailRow("細分類", fine) }
                    if let pos = item.partOfSpeech, !pos.isEmpty { self.detailRow("詞性", pos) }
                    if let cat = item.category, !cat.isEmpty { self.detailRow("分類", cat) }
                } else {
                    Text("這張圖片還沒生成卡片。")
                        .font(.tujiBody)
                        .foregroundStyle(.tujiInk3)
                }
                self.detailRow("狀態", self.image.status)

                BBtn(title: "刪除這張卡片", bg: .tujiCoral, fg: .white, fullWidth: true, icon: "trash") {
                    self.onDelete()
                    self.dismiss()
                }
                .padding(.top, Space.s2)
            }
            .padding(.horizontal, Space.s6)
            .padding(.vertical, Space.s4)
        }
        .background(.tujiBg)
        .navigationTitle(self.item?.lemma ?? tujiLocalized("圖片詳情"))
        .navigationBarTitleDisplayMode(.inline)
    }

    private func detailRow(_ title: LocalizedStringKey, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.tujiCaption)
                .foregroundStyle(.tujiInk3)
            Text(value)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(.tujiInk)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

#Preview {
    NavigationStack {
        AtlasManageView()
            .environment(AuthService.shared)
    }
}
