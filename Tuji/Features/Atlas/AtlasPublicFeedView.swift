// 公開圖鑑「瀏覽」頁（探索別人送審通過、已公開的 Atlas 項目）。
//
// 資料來源：GET /api/atlas/public（公開、吃 CDN 快取）。點作者進 AtlasAuthorProfileView，
// 點項目進 AtlasPublicDetailView（可收藏 / 檢舉）。
//
// 樣式沿用 CardsListView / WordTile（.tujiCard tile、2 欄 LazyVGrid、
// target-language badge、NukeUI LazyImage + 佔位）。

import Nuke
import NukeUI
import SwiftUI

// `AtlasPublicItem` now lives in Core/Models/Atlas.swift — the word detail
// section consumes the same model from the real API.

// MARK: - 列表頁

struct AtlasPublicFeedView: View {
    @State private var items: [AtlasPublicItem] = []
    @State private var loading = true
    @State private var loadError: String?
    @State private var langFilter: TargetLanguage? = nil
    @State private var selectedItem: AtlasPublicItem?
    @State private var selectedAuthorName: String?

    private var visibleItems: [AtlasPublicItem] {
        guard let langFilter else { return self.items }
        return self.items.filter { $0.targetLanguage == langFilter }
    }

    var body: some View {
        VStack(spacing: 0) {
            self.header
            self.filterRow
            self.content
        }
        .background(.tujiBg)
        // Tab root (社群), so the visible title is the in-view header below and
        // the system nav bar stays hidden — same pattern as CardsListView.
        // navigationTitle is metadata only (VoiceOver / back-button label).
        .navigationTitle("公開圖鑑")
        .toolbar(.hidden, for: .navigationBar)
        .navigationDestination(item: self.$selectedItem) { item in
            AtlasPublicDetailView(item: item)
        }
        .navigationDestination(item: self.$selectedAuthorName) { username in
            AtlasAuthorProfileView(username: username)
        }
        .task {
            await self.load()
        }
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("PUBLIC ATLAS")
                .font(.tujiOverline)
                .foregroundStyle(.tujiInk3)
            Text("公開圖鑑")
                .font(.tujiH2)
                .foregroundStyle(.tujiInk)
            Text("看看大家拍下、分享的單字")
                .font(.tujiCaption)
                .foregroundStyle(.tujiInk3)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Space.s6)
        .padding(.top, Space.s4)
        .padding(.bottom, Space.s3)
    }

    // MARK: Filter chips

    private var filterRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Space.s2) {
                self.chip(label: "全部", value: nil)
                self.chip(label: "英文", value: .en)
                self.chip(label: "日文", value: .ja)
            }
            .padding(.horizontal, Space.s6)
        }
        .padding(.bottom, Space.s3)
    }

    private func chip(label: String, value: TargetLanguage?) -> some View {
        let selected = self.langFilter == value
        return Button {
            self.langFilter = value
        } label: {
            Text(label)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(selected ? .white : .tujiInk2)
                .padding(.horizontal, Space.s4)
                .padding(.vertical, Space.s2)
                .background(selected ? Color.tujiTeal : Color.tujiCard, in: .capsule)
                .overlay(
                    Capsule().stroke(.tujiInk4.opacity(selected ? 0 : 0.25), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }

    // MARK: Content

    @ViewBuilder
    private var content: some View {
        if self.loading {
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
        } else if self.visibleItems.isEmpty {
            VStack(spacing: Space.s3) {
                Spacer()
                Image(systemName: "photo.on.rectangle.angled")
                    .font(.system(size: 40))
                    .foregroundStyle(.tujiInk4)
                Text(self.loadError == nil
                    ? tujiLocalized("這個語言還沒有公開項目")
                    : tujiLocalized("載入失敗，請稍後再試"))
                    .font(.tujiBody)
                    .foregroundStyle(.tujiInk3)
                if self.loadError != nil {
                    BBtn(title: "重試", fullWidth: false) {
                        Task { await self.load() }
                    }
                }
                Spacer()
            }
            .frame(maxWidth: .infinity)
        } else {
            ScrollView {
                LazyVGrid(
                    columns: [
                        GridItem(.flexible(), spacing: Space.s3),
                        GridItem(.flexible(), spacing: Space.s3)
                    ],
                    spacing: Space.s3
                ) {
                    ForEach(self.visibleItems) { item in
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
        }
    }

    // MARK: Load

    private func load() async {
        self.loading = true
        self.loadError = nil
        do {
            self.items = try await LiveAtlasRepository.shared.publicFeed()
        } catch {
            self.items = []
            self.loadError = error.localizedDescription
        }
        self.loading = false
    }
}

// MARK: - Tile

struct AtlasPublicTile: View {
    let item: AtlasPublicItem
    /// 點卡片主體（圖/詞）→ 開項目詳情。
    var onOpen: () -> Void = {}
    /// 點「by 作者」→ 開作者主頁。nil = 無作者，不可點。
    var onOpenAuthor: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack {
                Rectangle().fill(.tujiBg)
                LazyImage(url: self.item.imageURL) { state in
                    if let image = state.image {
                        image.resizable().aspectRatio(contentMode: .fill)
                    } else if state.error != nil {
                        self.placeholder
                    } else {
                        ProgressView().tint(.tujiTeal)
                    }
                }
                .pipeline(.shared)
            }
            .frame(height: 120)
            .clipped()
            .overlay(alignment: .topTrailing) {
                Text(self.item.langBadge)
                    .font(.system(size: 10, weight: .heavy))
                    .foregroundStyle(.tujiTeal)
                    .padding(.horizontal, Space.s2)
                    .padding(.vertical, 3)
                    .background(.tujiTealSoft, in: .capsule)
                    .padding(Space.s2)
            }
            // 卡片主體點擊區（圖）→ 詳情
            .contentShape(Rectangle())
            .onTapGesture { self.onOpen() }

            VStack(alignment: .leading, spacing: 2) {
                Text(self.item.lemma)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.tujiInk)
                    .lineLimit(1)
                Text(self.item.displayZhHant)
                    .font(.tujiCaption)
                    .foregroundStyle(.tujiInk3)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                    .onTapGesture { self.onOpen() }
                if let name = self.item.attributionName, !name.isEmpty {
                    if let onOpenAuthor {
                        Button(action: onOpenAuthor) {
                            Text("by \(name)")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.tujiTeal)
                                .lineLimit(1)
                                .padding(.top, 1)
                        }
                        .buttonStyle(.plain)
                    } else {
                        Text("by \(name)")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.tujiInk4)
                            .lineLimit(1)
                            .padding(.top, 1)
                    }
                }
            }
            .padding(Space.s3)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(.tujiCard)
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg)
                .stroke(.tujiInk4.opacity(0.25), lineWidth: 1)
        )
    }

    private var placeholder: some View {
        ZStack {
            LinearGradient(
                colors: [.tujiTealSoft, .tujiBg],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Image(systemName: "photo")
                .font(.system(size: 22))
                .foregroundStyle(.tujiInk4)
        }
    }
}

// MARK: - 詳情頁

struct AtlasPublicDetailView: View {
    let item: AtlasPublicItem

    @State private var saved = false
    @State private var saveCount: Int?
    @State private var busy = false
    @State private var actionError: String?
    @State private var reportSent = false
    @State private var showReport = false
    @State private var selectedAuthorName: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.s4) {
                ZStack {
                    Rectangle().fill(.tujiBg)
                    LazyImage(url: self.item.imageURL) { state in
                        if let image = state.image {
                            image.resizable().aspectRatio(contentMode: .fill)
                        } else {
                            Image(systemName: "photo")
                                .font(.system(size: 32))
                                .foregroundStyle(.tujiInk4)
                        }
                    }
                    .pipeline(.shared)
                }
                .frame(height: 240)
                .frame(maxWidth: .infinity)
                .clipped()
                .clipShape(RoundedRectangle(cornerRadius: Radius.xl))

                HStack(spacing: Space.s2) {
                    Text(self.item.lemma)
                        .font(.tujiH1)
                        .foregroundStyle(.tujiInk)
                    Text(self.item.langBadge)
                        .font(.system(size: 11, weight: .heavy))
                        .foregroundStyle(.tujiTeal)
                        .padding(.horizontal, Space.s2)
                        .padding(.vertical, 3)
                        .background(.tujiTealSoft, in: .capsule)
                }

                Text(self.item.displayZhHant)
                    .font(.tujiBody)
                    .foregroundStyle(.tujiInk2)

                if let category = self.item.category {
                    self.metaRow(icon: "square.grid.2x2", text: category)
                }
                if let name = self.item.attributionName {
                    Button {
                        self.selectedAuthorName = name
                    } label: {
                        HStack(spacing: Space.s2) {
                            Image(systemName: "person.crop.circle")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(.tujiTeal)
                                .frame(width: 18)
                            Text("由 \(name) 分享")
                                .font(.tujiCaption)
                                .foregroundStyle(.tujiTeal)
                            Image(systemName: "chevron.right")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(.tujiInk4)
                        }
                    }
                    .buttonStyle(.plain)
                }
                if let date = self.item.publishedAt {
                    self.metaRow(icon: "calendar", text: date)
                }

                if let saveCount, saveCount > 0 {
                    self.metaRow(icon: "bookmark", text: tujiLocalized("\(saveCount) 人收藏"))
                }

                // Saving is the consumption path: it does NOT use up the user's
                // 自製圖鑑 capacity (docs/COMMUNITY_ATLAS_PLAN.md §4.1).
                Button {
                    self.toggleSave()
                } label: {
                    HStack {
                        Image(systemName: self.saved ? "checkmark" : "plus")
                        Text(self.saved ? "已收藏" : "收進我的圖鑑")
                    }
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Space.s3)
                    .background(self.saved ? Color.tujiInk4 : Color.tujiTeal, in: .capsule)
                }
                .buttonStyle(.plain)
                .disabled(self.busy)
                .opacity(self.busy ? 0.6 : 1)
                .padding(.top, Space.s2)

                if let actionError {
                    Text(actionError)
                        .font(.tujiCaption)
                        .foregroundStyle(.tujiCoral)
                        .frame(maxWidth: .infinity, alignment: .center)
                }

                Button {
                    self.showReport = true
                } label: {
                    Text(self.reportSent ? "已收到檢舉" : "檢舉這個項目")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(self.reportSent ? .tujiInk4 : .tujiCoral)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, Space.s2)
                }
                .buttonStyle(.plain)
                .disabled(self.reportSent)
            }
            .padding(Space.s6)
        }
        .background(.tujiBg)
        .navigationTitle(self.item.lemma)
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: self.$selectedAuthorName) { username in
            AtlasAuthorProfileView(username: username)
        }
        .task {
            AnalyticsService.shared.track(.atlasPublicItemViewed)
        }
        .confirmationDialog("檢舉原因", isPresented: self.$showReport, titleVisibility: .visible) {
            ForEach(AtlasReportReason.allCases) { reason in
                Button(reason.label, role: .destructive) {
                    self.report(reason)
                }
            }
            Button("取消", role: .cancel) {}
        }
    }

    // MARK: - Actions

    private func toggleSave() {
        guard !self.busy else { return }
        self.busy = true
        self.actionError = nil
        let wasSaved = self.saved
        Task {
            do {
                let repo = LiveAtlasRepository.shared
                let response = wasSaved
                    ? try await repo.unsave(slug: self.item.slug)
                    : try await repo.save(slug: self.item.slug)
                self.saved = response.saved
                self.saveCount = response.saveCount
                if response.saved {
                    AnalyticsService.shared.track(.atlasPublicSaved)
                }
            } catch {
                self.actionError = error.localizedDescription
            }
            self.busy = false
        }
    }

    private func report(_ reason: AtlasReportReason) {
        self.actionError = nil
        Task {
            do {
                try await LiveAtlasRepository.shared.report(
                    slug: self.item.slug,
                    reason: reason,
                    detail: nil
                )
                self.reportSent = true
            } catch {
                self.actionError = error.localizedDescription
            }
        }
    }

    private func metaRow(icon: String, text: String) -> some View {
        HStack(spacing: Space.s2) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.tujiInk4)
                .frame(width: 18)
            Text(text)
                .font(.tujiCaption)
                .foregroundStyle(.tujiInk3)
        }
    }
}

// MARK: - Preview

// Previews hit the live public endpoints (no auth needed for reads), so an
// empty wall here just means the dev backend has no approved items yet.
#Preview("公開牆") {
    NavigationStack {
        AtlasPublicFeedView()
    }
    .environment(SettingsStore.shared)
}
