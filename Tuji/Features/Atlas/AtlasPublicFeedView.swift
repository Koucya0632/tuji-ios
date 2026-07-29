// 公開圖鑑「瀏覽」頁 —— 大家整理的具名合集（MOJi 風格）。
//
// 資料來源：GET /api/atlas/public/collections?lang=（公開、吃 CDN 快取）。列表**自動依
// 使用者當前學習語言過濾**（學日文只看日文合集），無手動語言切換。點合集卡片進
// AtlasCollectionDetailView（目錄/簡介），再點項目進 AtlasPublicDetailView（收藏 / 檢舉）。

import Nuke
import NukeUI
import SwiftUI

// `AtlasPublicItem` now lives in Core/Models/Atlas.swift — the word detail
// section consumes the same model from the real API.

// MARK: - 列表頁（合集）

struct AtlasPublicFeedView: View {
    @Environment(SettingsStore.self) private var settings
    @Environment(CommunityFeedRefresh.self) private var feedRefresh

    @State private var vm = PublicFeedVM()
    @State private var selectedCollection: AtlasCollection?

    /// The feed follows the user's current learning direction — Japanese learners
    /// see Japanese collections, English learners see English ones. There is no
    /// manual language switch on this screen, by product decision.
    private var targetLanguage: TargetLanguage {
        self.settings.current.learningDirection.targetLanguage
    }

    var body: some View {
        VStack(spacing: 0) {
            self.header
            self.content
        }
        .background(.tujiBg)
        // Tab root (社群), so the visible title is the in-view header below and
        // the system nav bar stays hidden — same pattern as CardsListView.
        .navigationTitle("公開圖鑑")
        .toolbar(.hidden, for: .navigationBar)
        .navigationDestination(item: self.$selectedCollection) { collection in
            AtlasCollectionDetailView(slug: collection.slug, preview: collection)
        }
        // Re-runs on first appearance AND whenever the learning direction flips, so
        // switching 日文/英文 圖鑑 reloads the feed for the new language. The pending
        // publish signal is consumed here (the view owns the global) and handed to
        // the VM as a plain flag.
        .task(id: self.targetLanguage) {
            await self.vm.load(
                lang: self.targetLanguage,
                pendingForce: self.feedRefresh.consume()
            )
        }
    }

    // MARK: Header

    /// This tab is other people's work — 我的合集 lives in 我的, with the rest of
    /// what the user makes. What stays here is the CTA at the foot of the feed,
    /// where "看別人的 → 我也要做一個" actually happens.
    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("PUBLIC ATLAS")
                .font(.tujiOverline)
                .foregroundStyle(.tujiInk3)
            Text("公開圖鑑")
                .font(.tujiH2)
                .foregroundStyle(.tujiInk)
            Text("看看大家整理的單字合集")
                .font(.tujiCaption)
                .foregroundStyle(.tujiInk3)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Space.s6)
        .padding(.top, Space.s4)
        .padding(.bottom, Space.s3)
    }

    // MARK: Content

    @ViewBuilder
    private var content: some View {
        if case .loading = self.vm.phase {
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
        } else {
            // Empty and populated states share one ScrollView so pull-to-refresh
            // works in both — the empty case is exactly when the user needs it.
            ScrollView {
                if self.vm.collections.isEmpty {
                    self.emptyState
                        .containerRelativeFrame(.vertical)
                } else {
                    LazyVStack(spacing: Space.s3) {
                        ForEach(self.vm.collections) { collection in
                            AtlasCollectionCard(collection: collection) {
                                self.selectedCollection = collection
                            }
                        }
                        self.myCollectionsCTA
                            .padding(.top, Space.s3)
                    }
                    .padding(.horizontal, Space.s6)
                    .padding(.top, Space.s1)
                    .padding(.bottom, Space.s8)
                }
            }
            // Allow the pull gesture even when the content is shorter than the viewport.
            .scrollBounceBehavior(.always, axes: .vertical)
            .refreshable { await self.vm.load(lang: self.targetLanguage, forceReload: true) }
        }
    }

    /// Sits at the foot of the feed, after the user has seen what others made.
    /// It's a shortcut into 我的合集, not a second home for it.
    private var myCollectionsCTA: some View {
        NavigationLink(value: NavRoute.atlasMyCollections) {
            HStack(spacing: Space.s3) {
                Image(systemName: "rectangle.stack.badge.plus")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(.tujiTeal)
                VStack(alignment: .leading, spacing: 2) {
                    Text("建立你自己的合集")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.tujiInk)
                    Text("把你公開的圖鑑整理成一份主題")
                        .font(.tujiCaption)
                        .foregroundStyle(.tujiInk3)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.tujiInk4)
            }
            .padding(Space.s4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.tujiTealSoft, in: .rect(cornerRadius: Radius.lg))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var emptyState: some View {
        VStack(spacing: Space.s3) {
            Spacer()
            Image(systemName: "square.stack.3d.up.slash")
                .font(.system(size: 40))
                .foregroundStyle(.tujiInk4)
            Text(self.vm.errorMessage == nil
                ? tujiLocalized("這個語言還沒有公開合集")
                : tujiLocalized("載入失敗，請稍後再試"))
                .font(.tujiBody)
                .foregroundStyle(.tujiInk3)
            if self.vm.errorMessage != nil {
                BBtn(title: "重試", fullWidth: false) {
                    Task { await self.vm.load(lang: self.targetLanguage, forceReload: true) }
                }
            } else {
                // Nothing published in this language yet is exactly when being
                // the first one to do it is worth offering.
                self.myCollectionsCTA
                    .padding(.horizontal, Space.s6)
                    .padding(.top, Space.s3)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - 合集卡片

struct AtlasCollectionCard: View {
    let collection: AtlasCollection
    var onOpen: () -> Void = {}
    /// Off on the author profile, where every card is by the same person and the
    /// byline would just repeat the header down the whole list. On the browse
    /// feed it's the main thing distinguishing one card from the next.
    var showsAuthor = true

    private var pose: MascotPose {
        MascotPose(rawValue: self.collection.author?.avatar ?? "") ?? .face
    }

    var body: some View {
        Button(action: self.onOpen) {
            HStack(spacing: Space.s3) {
                self.cover
                VStack(alignment: .leading, spacing: 6) {
                    Text(self.collection.title)
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(.tujiInk)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    // Nothing at all when the author has no confirmed public
                    // identity — the card must not fall back to a handle.
                    if self.showsAuthor, let author = self.collection.author {
                        HStack(spacing: Space.s2) {
                            MascotAvatar(pose: self.pose, size: 22)
                            Text(author.displayName)
                                .font(.tujiCaption)
                                .foregroundStyle(.tujiInk2)
                                .lineLimit(1)
                        }
                    }
                    HStack(spacing: Space.s3) {
                        Label("\(self.collection.itemCount)", systemImage: "square.stack")
                        if self.collection.saveCount > 0 {
                            Label("\(self.collection.saveCount)", systemImage: "bookmark")
                        }
                    }
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.tujiInk3)
                    if let desc = self.collection.description, !desc.isEmpty {
                        Text(desc)
                            .font(.tujiCaption)
                            .foregroundStyle(.tujiInk3)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(Space.s3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.tujiCard)
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.lg)
                    .stroke(.tujiInk4.opacity(0.25), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private var cover: some View {
        ZStack {
            Rectangle().fill(.tujiBg)
            LazyImage(url: self.collection.coverURL) { state in
                if let image = state.image {
                    image.resizable().aspectRatio(contentMode: .fill)
                } else if state.error != nil {
                    Image(systemName: "square.stack.3d.up")
                        .font(.system(size: 22))
                        .foregroundStyle(.tujiInk4)
                } else {
                    ProgressView().tint(.tujiTeal)
                }
            }
            .pipeline(.shared)
        }
        .frame(width: 84, height: 84)
        .clipped()
        .clipShape(RoundedRectangle(cornerRadius: Radius.md))
        .overlay(alignment: .topTrailing) {
            Text(self.collection.langBadge)
                .font(.system(size: 9, weight: .heavy))
                .foregroundStyle(.tujiTeal)
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(.tujiTealSoft, in: .capsule)
                .padding(4)
        }
    }
}

// MARK: - Tile

struct AtlasPublicTile: View {
    let item: AtlasPublicItem
    /// 點卡片主體（圖/詞）→ 開項目詳情。
    var onOpen: () -> Void = {}
    /// 點「by 作者」→ 開作者主頁。nil = 無作者，不可點。
    var onOpenAuthor: (() -> Void)?

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
                if let author = self.item.author {
                    if let onOpenAuthor {
                        Button(action: onOpenAuthor) {
                            Text("by \(author.displayName)")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.tujiTeal)
                                .lineLimit(1)
                                .padding(.top, 1)
                        }
                        .buttonStyle(.plain)
                    } else {
                        Text("by \(author.displayName)")
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

    @State private var vm: AtlasPublicDetailVM
    @State private var showReport = false
    /// The author route is keyed by handle, never by display name — two people
    /// may share a name, and only the handle is a valid path component.
    @State private var selectedAuthorHandle: String?

    init(item: AtlasPublicItem, repo: AtlasItemConsuming = LiveAtlasRepository.shared) {
        self.item = item
        _vm = State(initialValue: AtlasPublicDetailVM(item: item, repo: repo))
    }

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
                if let author = self.item.author {
                    Button {
                        self.selectedAuthorHandle = author.handle
                    } label: {
                        HStack(spacing: Space.s2) {
                            Image(systemName: "person.crop.circle")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(.tujiTeal)
                                .frame(width: 18)
                            Text("由 \(author.displayName) 分享")
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

                if let saveCount = self.vm.saveCount, saveCount > 0 {
                    self.metaRow(icon: "bookmark", text: tujiLocalized("\(saveCount) 人收藏"))
                }

                // Saving is the consumption path: it does NOT use up the user's
                // 自製圖鑑 capacity (docs/COMMUNITY_ATLAS_PLAN.md §4.1).
                Button {
                    Task {
                        // The VM owns the state; analytics stays in the view.
                        if await self.vm.toggleSave() == true {
                            AnalyticsService.shared.track(.atlasPublicSaved)
                        }
                    }
                } label: {
                    HStack {
                        Image(systemName: self.vm.saved ? "checkmark" : "plus")
                        Text(self.vm.saved ? "已收藏" : "收進我的圖鑑")
                    }
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Space.s3)
                    .background(self.vm.saved ? Color.tujiInk4 : Color.tujiTeal, in: .capsule)
                }
                .buttonStyle(.plain)
                .disabled(self.vm.busy)
                .opacity(self.vm.busy ? 0.6 : 1)
                .padding(.top, Space.s2)

                if let actionError = self.vm.actionError {
                    Text(actionError)
                        .font(.tujiCaption)
                        .foregroundStyle(.tujiCoral)
                        .frame(maxWidth: .infinity, alignment: .center)
                }

                Button {
                    self.showReport = true
                } label: {
                    Text(self.vm.reportSent ? "已收到檢舉" : "檢舉這個項目")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(self.vm.reportSent ? .tujiInk4 : .tujiCoral)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, Space.s2)
                }
                .buttonStyle(.plain)
                .disabled(self.vm.reportSent)
            }
            .padding(Space.s6)
        }
        .background(.tujiBg)
        .navigationTitle(self.item.lemma)
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: self.$selectedAuthorHandle) { handle in
            AtlasAuthorProfileView(handle: handle)
        }
        .task {
            AnalyticsService.shared.track(.atlasPublicItemViewed)
        }
        .confirmationDialog("檢舉原因", isPresented: self.$showReport, titleVisibility: .visible) {
            ForEach(AtlasReportReason.allCases) { reason in
                Button(reason.label, role: .destructive) {
                    Task { await self.vm.report(reason) }
                }
            }
            Button("取消", role: .cancel) {}
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
    .environment(CommunityFeedRefresh())
}
