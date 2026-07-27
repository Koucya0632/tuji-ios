// 公開合集詳情（MOJi 風格）：封面做主題化 header + 目錄 / 簡介 tab。
//
// 資料來源：GET /api/atlas/public/collections/{slug}。目錄裡的項目沿用 AtlasPublicTile，
// 點進去是既有的 AtlasPublicDetailView（逐張收藏 / 檢舉）——收藏維持逐張，合集層級只顯示數字。

import Nuke
import NukeUI
import SwiftUI

struct AtlasCollectionDetailView: View {
    @State private var vm: CollectionDetailVM
    @State private var tab: Tab = .catalog
    @State private var selectedItem: AtlasPublicItem?
    @State private var selectedAuthorName: String?

    enum Tab: Hashable { case catalog, about }

    /// `preview` is the card data from the feed, so the header renders instantly
    /// while the member items load.
    init(slug: String, preview: AtlasCollection? = nil) {
        _vm = State(initialValue: CollectionDetailVM(slug: slug, preview: preview))
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                if let collection = self.vm.collection {
                    self.header(collection)
                    self.tabBar
                    self.tabContent(collection)
                } else if case .loading = self.vm.phase {
                    ProgressView()
                        .tint(.tujiTeal)
                        .padding(.top, Space.s12)
                } else {
                    self.errorState
                }
            }
        }
        .background(.tujiBg)
        .navigationTitle(self.vm.collection?.title ?? tujiLocalized("合集"))
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: self.$selectedItem) { item in
            AtlasPublicDetailView(item: item)
        }
        .navigationDestination(item: self.$selectedAuthorName) { username in
            AtlasAuthorProfileView(username: username)
        }
        .task(id: self.vm.slug) {
            await self.vm.load()
        }
    }

    // MARK: Header

    private func header(_ collection: AtlasCollection) -> some View {
        ZStack(alignment: .bottomLeading) {
            // Cover as a darkened backdrop so overlaid white text stays legible.
            LazyImage(url: collection.coverURL) { state in
                if let image = state.image {
                    image.resizable().aspectRatio(contentMode: .fill)
                } else {
                    LinearGradient(
                        colors: [.tujiTeal, .tujiTealSoft],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                }
            }
            .pipeline(.shared)
            .frame(height: 190)
            .frame(maxWidth: .infinity)
            .clipped()
            .overlay(Color.black.opacity(0.32))

            HStack(alignment: .bottom, spacing: Space.s3) {
                LazyImage(url: collection.coverURL) { state in
                    if let image = state.image {
                        image.resizable().aspectRatio(contentMode: .fill)
                    } else {
                        Color.tujiTealSoft
                    }
                }
                .pipeline(.shared)
                .frame(width: 84, height: 84)
                .clipped()
                .clipShape(RoundedRectangle(cornerRadius: Radius.md))
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.md)
                        .stroke(.white.opacity(0.5), lineWidth: 1)
                )

                VStack(alignment: .leading, spacing: 6) {
                    Text(collection.title)
                        .font(.tujiH2)
                        .foregroundStyle(.white)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    Button {
                        self.selectedAuthorName = collection.author.username
                    } label: {
                        HStack(spacing: 6) {
                            MascotAvatar(
                                pose: MascotPose(rawValue: collection.author.avatar) ?? .face,
                                size: 22
                            )
                            Text(collection.author.displayName)
                                .font(.tujiCaption)
                                .foregroundStyle(.white.opacity(0.95))
                                .lineLimit(1)
                        }
                    }
                    .buttonStyle(.plain)
                    HStack(spacing: Space.s3) {
                        self.stat(icon: "square.stack", title: "內容", value: collection.itemCount)
                        self.stat(icon: "bookmark", title: "收藏", value: collection.saveCount)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(Space.s4)
        }
    }

    private func stat(icon: String, title: LocalizedStringKey, value: Int) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon).font(.system(size: 11, weight: .bold))
            Text(title).font(.system(size: 12, weight: .semibold))
            Text("\(value)").font(.system(size: 12, weight: .heavy))
        }
        .foregroundStyle(.white.opacity(0.95))
    }

    // MARK: Tabs

    private var tabBar: some View {
        HStack(spacing: Space.s5) {
            self.tabButton("目錄", .catalog)
            self.tabButton("簡介", .about)
            Spacer()
        }
        .padding(.horizontal, Space.s6)
        .padding(.top, Space.s4)
        .padding(.bottom, Space.s2)
    }

    private func tabButton(_ label: LocalizedStringKey, _ value: Tab) -> some View {
        let selected = self.tab == value
        return Button {
            self.tab = value
        } label: {
            VStack(spacing: 4) {
                Text(label)
                    .font(.system(size: 15, weight: selected ? .bold : .medium))
                    .foregroundStyle(selected ? .tujiInk : .tujiInk3)
                Capsule()
                    .fill(selected ? Color.tujiTeal : .clear)
                    .frame(width: 22, height: 3)
            }
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func tabContent(_ collection: AtlasCollection) -> some View {
        switch self.tab {
        case .catalog:
            if self.vm.items.isEmpty, case .loading = self.vm.phase {
                ProgressView().tint(.tujiTeal).padding(.vertical, Space.s8)
            } else if self.vm.items.isEmpty {
                Text("這個合集還沒有項目")
                    .font(.tujiBody)
                    .foregroundStyle(.tujiInk3)
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
                    ForEach(self.vm.items) { item in
                        AtlasPublicTile(
                            item: item,
                            onOpen: { self.selectedItem = item },
                            onOpenAuthor: item.attributionName.map { name in
                                { self.selectedAuthorName = name }
                            }
                        )
                    }
                }
                .padding(.horizontal, Space.s6)
                .padding(.bottom, Space.s8)
            }
        case .about:
            let about = collection.description.flatMap { $0.isEmpty ? nil : $0 }
            Text(about ?? tujiLocalized("作者還沒有填寫簡介。"))
                .font(.tujiBody)
                .foregroundStyle(about == nil ? .tujiInk3 : .tujiInk2)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, Space.s6)
                .padding(.top, Space.s2)
                .padding(.bottom, Space.s8)
        }
    }

    private var errorState: some View {
        VStack(spacing: Space.s3) {
            Image(systemName: "square.stack.3d.up.slash")
                .font(.system(size: 40))
                .foregroundStyle(.tujiInk4)
            Text(self.vm.errorMessage == nil
                ? tujiLocalized("找不到這個合集")
                : tujiLocalized("載入失敗，請稍後再試"))
                .font(.tujiBody)
                .foregroundStyle(.tujiInk3)
            BBtn(title: "重試", fullWidth: false) {
                Task { await self.vm.load() }
            }
        }
        .padding(.top, Space.s12)
    }
}
