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
    @Environment(AuthService.self) private var auth
    @Environment(CollectionBookmarkStore.self) private var bookmarks

    @State private var browsing = PublicAtlasBrowsingModel()
    @State private var selectedCollection: AtlasCollection?
    @State private var section: PublicAtlasBrowsingModel.Shelf = .explore
    @State private var savedShelfMounted = false

    /// The feed follows the user's current learning direction — Japanese learners
    /// see Japanese collections, English learners see English ones. There is no
    /// manual language switch on this screen, by product decision.
    private var targetLanguage: TargetLanguage {
        self.settings.current.learningDirection.targetLanguage
    }

    var body: some View {
        VStack(spacing: 0) {
            self.header
            self.segmentedControl
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
        // Reconcile all product context through one state module. The view still
        // owns SwiftUI environment objects and translates them into plain values.
        .task(id: self.browsingLoadKey) {
            if self.section == .saved { self.savedShelfMounted = true }
            await self.browsing.update(
                shelf: self.section,
                language: self.targetLanguage,
                isSignedIn: self.isSignedIn,
                pendingExploreRefresh: self.feedRefresh.consume()
            )
        }
        .onChange(of: self.bookmarks.revision) { _, _ in
            guard let change = self.bookmarks.lastChange else { return }
            self.browsing.applyConfirmedBookmark(
                collection: change.collection,
                isSaved: change.saved,
                language: self.targetLanguage
            )
        }
    }

    // MARK: Header

    /// This tab is other people's work — 我的合集 lives in 我的, with the rest of
    /// what the user makes.
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

    private var segmentedControl: some View {
        Picker("公開圖鑑區段", selection: self.$section) {
            ForEach(PublicAtlasBrowsingModel.Shelf.allCases) { section in
                Text(self.title(for: section)).tag(section)
            }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal, Space.s6)
        .padding(.bottom, Space.s3)
    }

    private var content: some View {
        ZStack {
            self.exploreContent
                .opacity(self.section == .explore ? 1 : 0)
                .allowsHitTesting(self.section == .explore)
                .accessibilityHidden(self.section != .explore)

            if self.savedShelfMounted || self.section == .saved {
                self.savedContent
                    .opacity(self.section == .saved ? 1 : 0)
                    .allowsHitTesting(self.section == .saved)
                    .accessibilityHidden(self.section != .saved)
            }
        }
        .onChange(of: self.section) { _, value in
            if value == .saved { self.savedShelfMounted = true }
        }
    }

    @ViewBuilder
    private var exploreContent: some View {
        if case .loading = self.browsing.explore.phase {
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
                if self.browsing.explore.collections.isEmpty {
                    self.emptyState
                        .containerRelativeFrame(.vertical)
                } else {
                    LazyVStack(spacing: Space.s3) {
                        ForEach(self.browsing.explore.collections) { collection in
                            AtlasCollectionCard(collection: collection) {
                                self.selectedCollection = collection
                            }
                        }
                    }
                    .padding(.horizontal, Space.s6)
                    .padding(.top, Space.s1)
                    .padding(.bottom, Space.s8)
                }
            }
            // Allow the pull gesture even when the content is shorter than the viewport.
            .scrollBounceBehavior(.always, axes: .vertical)
            .refreshable {
                await self.browsing.refresh(
                    shelf: .explore,
                    language: self.targetLanguage,
                    isSignedIn: self.isSignedIn
                )
            }
        }
    }

    @ViewBuilder
    private var savedContent: some View {
        if !self.isSignedIn {
            VStack(spacing: Space.s4) {
                Spacer()
                Text("登入後才能查看已收藏的合集")
                    .font(.tujiBody)
                    .foregroundStyle(.tujiInk3)
                BBtn(title: "登入", fullWidth: false) {
                    self.auth.exitGuestMode()
                }
                Spacer()
            }
            .frame(maxWidth: .infinity)
        } else if case .loading = self.browsing.saved.phase,
                  self.browsing.saved.collections.isEmpty
        {
            ProgressView()
                .tint(.tujiTeal)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                if self.browsing.saved.collections.isEmpty {
                    Text(self.browsing.saved.errorMessage == nil
                        ? self.savedEmptyText
                        : tujiLocalized("載入失敗，請稍後再試"))
                        .font(.tujiBody)
                        .foregroundStyle(.tujiInk3)
                        .frame(maxWidth: .infinity)
                        .containerRelativeFrame(.vertical)
                } else {
                    LazyVStack(spacing: Space.s3) {
                        ForEach(self.browsing.saved.collections) { collection in
                            AtlasCollectionCard(collection: collection) {
                                self.selectedCollection = collection
                            }
                        }
                    }
                    .padding(.horizontal, Space.s6)
                    .padding(.top, Space.s1)
                    .padding(.bottom, Space.s8)
                }
            }
            .scrollBounceBehavior(.always, axes: .vertical)
            .refreshable {
                await self.browsing.refresh(
                    shelf: .saved,
                    language: self.targetLanguage,
                    isSignedIn: self.isSignedIn
                )
            }
        }
    }

    private var isSignedIn: Bool {
        if case .signedIn = self.auth.state { return true }
        return false
    }

    private var browsingLoadKey: String {
        "\(self.section.rawValue)-\(self.targetLanguage.rawValue)-\(self.isSignedIn)"
    }

    private func title(for shelf: PublicAtlasBrowsingModel.Shelf) -> LocalizedStringKey {
        switch shelf {
        case .explore: "探索"
        case .saved: "已收藏"
        }
    }

    private var savedEmptyText: String {
        switch self.targetLanguage {
        case .ja: tujiLocalized("目前沒有收藏的日文合集")
        case .en: tujiLocalized("目前沒有收藏的英文合集")
        }
    }

    private var emptyState: some View {
        VStack(spacing: Space.s3) {
            Spacer()
            Image(systemName: "square.stack.3d.up.slash")
                .font(.system(size: 40))
                .foregroundStyle(.tujiInk4)
            Text(self.browsing.explore.errorMessage == nil
                ? tujiLocalized("這個語言還沒有公開合集")
                : tujiLocalized("載入失敗，請稍後再試"))
                .font(.tujiBody)
                .foregroundStyle(.tujiInk3)
            if self.browsing.explore.errorMessage != nil {
                BBtn(title: "重試", fullWidth: false) {
                    Task {
                        await self.browsing.refresh(
                            shelf: .explore,
                            language: self.targetLanguage,
                            isSignedIn: self.isSignedIn
                        )
                    }
                }
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
                            ProfileAvatar(avatar: author.avatar, size: 22)
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
    @Environment(AuthService.self) private var auth
    @Environment(MasteryStore.self) private var mastery
    @Environment(SettingsStore.self) private var settings
    @State private var vm: AtlasPublicDetailVM
    @State private var showReport = false
    @State private var showStopLearningPrompt = false
    /// The author route is keyed by handle, never by display name — two people
    /// may share a name, and only the handle is a valid path component.
    @State private var selectedAuthorHandle: String?

    init(
        item: AtlasPublicItem,
        repo: AtlasItemConsuming = LiveAtlasRepository.shared,
        itemReader: PublicItemsReading = LiveAtlasRepository.shared
    ) {
        _vm = State(initialValue: AtlasPublicDetailVM(
            item: item,
            repo: repo,
            itemReader: itemReader
        ))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.s4) {
                if self.vm.saved {
                    MasteryBar(score: self.mastery.score(for: "saved:\(self.vm.item.slug)"))
                }

                self.imageCard

                if let word = self.vm.item.learningWord {
                    self.titleRow(word)
                } else {
                    self.previewTitle
                }

                self.socialLearningRow

                if let word = self.vm.item.learningWord {
                    WordDetailSections(word: word)
                }

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
        .navigationTitle(self.vm.item.lemma)
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: self.$selectedAuthorHandle) { handle in
            AtlasAuthorProfileView(handle: handle)
        }
        .task {
            AnalyticsService.shared.track(.atlasPublicItemViewed)
            async let detail: Void = self.vm.loadDetail()
            async let saveState: Void = self.vm.loadSaveState()
            async let mastery: Void = self.mastery.loadIfNeeded()
            _ = await (detail, saveState, mastery)
        }
        .tujiPrompt(
            isPresented: self.$showStopLearningPrompt,
            style: .confirmation,
            title: "停止學習這個單詞？",
            primary: TujiPromptAction("確定", role: .destructive) {
                Task { _ = await self.vm.toggleSave() }
            },
            secondary: TujiPromptAction("取消", role: .cancel) {}
        )
        .confirmationDialog("檢舉原因", isPresented: self.$showReport, titleVisibility: .visible) {
            ForEach(AtlasReportReason.allCases) { reason in
                Button(reason.label, role: .destructive) {
                    Task { await self.vm.report(reason) }
                }
            }
            Button("取消", role: .cancel) {}
        }
    }

    private var imageCard: some View {
        ZStack {
            RoundedRectangle(cornerRadius: Radius.xl)
                .fill(.tujiBg)
            LazyImage(url: self.vm.item.imageURL) { state in
                if let image = state.image {
                    image.resizable()
                        .aspectRatio(contentMode: .fit)
                        .padding(Space.s4)
                } else if state.error != nil {
                    Image(systemName: "photo")
                        .font(.system(size: 28))
                        .foregroundStyle(.tujiInk4)
                } else {
                    ProgressView().tint(.tujiTeal)
                }
            }
            .pipeline(.shared)
        }
        .frame(height: 220)
        .frame(maxWidth: .infinity)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.xl)
                .stroke(.tujiInk4.opacity(0.2), lineWidth: 1)
        )
    }

    private var previewTitle: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack(spacing: Space.s2) {
                Text(self.vm.item.lemma)
                    .font(.tujiH1)
                    .foregroundStyle(.tujiInk)
                Text(self.vm.item.langBadge)
                    .font(.system(size: 11, weight: .heavy))
                    .foregroundStyle(.tujiTeal)
                    .padding(.horizontal, Space.s2)
                    .padding(.vertical, 3)
                    .background(.tujiTealSoft, in: .capsule)
            }
            Text(self.vm.item.displayZhHant)
                .font(.tujiBody)
                .foregroundStyle(.tujiInk2)
        }
    }

    private func titleRow(_ word: Word) -> some View {
        HStack(alignment: .top, spacing: Space.s4) {
            VStack(alignment: .leading, spacing: Space.s2) {
                Text(word.word)
                    .font(.tujiH1)
                    .foregroundStyle(.tujiInk)
                    .lineLimit(2)
                    .minimumScaleFactor(0.6)
                HStack(spacing: Space.s2) {
                    if let pronunciation = word.pronunciation, !pronunciation.isEmpty {
                        Text(pronunciation)
                            .font(.tujiMono)
                            .foregroundStyle(.tujiInk2)
                    }
                    if let partOfSpeech = word.partOfSpeech, !partOfSpeech.isEmpty {
                        Text(localizedPartOfSpeech(
                            partOfSpeech,
                            language: self.settings.current.uiLanguage
                        ))
                        .font(.tujiCaption)
                        .italic()
                        .foregroundStyle(.tujiInk3)
                    }
                    if let cefr = word.cefrLevel, !cefr.isEmpty {
                        Text(cefr)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.tujiTeal)
                            .padding(.horizontal, Space.s2)
                            .padding(.vertical, 2)
                            .background(.tujiTealSoft, in: .capsule)
                    }
                }
            }
            Spacer()
            PronunciationButton(
                text: word.word,
                language: word.wordLanguage,
                audioUrls: word.audioUrls,
                size: 48
            )
        }
    }

    private var socialLearningRow: some View {
        HStack(spacing: Space.s2) {
            if let author = self.vm.item.author {
                Button {
                    self.selectedAuthorHandle = author.handle
                } label: {
                    HStack(spacing: 6) {
                        ProfileAvatar(avatar: author.avatar, size: 24)
                        Text(author.displayName)
                            .font(.tujiCaption)
                            .foregroundStyle(.tujiTeal)
                            .lineLimit(1)
                    }
                }
                .buttonStyle(.plain)
            }

            Text("\(self.vm.saveCount ?? 0) 人學習中")
                .font(.tujiCaption)
                .foregroundStyle(.tujiInk3)
                .lineLimit(1)

            Spacer(minLength: Space.s2)

            if self.isOwnItem {
                self.learningPillLabel(icon: nil, title: "你的分享", active: true)
            } else {
                Button {
                    if self.vm.saved {
                        self.showStopLearningPrompt = true
                    } else {
                        Task {
                            if await self.vm.toggleSave() == true {
                                AnalyticsService.shared.track(.atlasPublicSaved)
                            }
                        }
                    }
                } label: {
                    self.learningPillLabel(
                        icon: self.vm.saved ? "checkmark" : "plus",
                        title: self.vm.saved ? "學習中" : "加入學習",
                        active: self.vm.saved
                    )
                }
                .buttonStyle(.plain)
                .disabled(self.vm.busy)
                .opacity(self.vm.busy ? 0.6 : 1)
            }
        }
    }

    private func learningPillLabel(
        icon: String?,
        title: LocalizedStringKey,
        active: Bool
    )
        -> some View
    {
        HStack(spacing: 5) {
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .bold))
            }
            Text(title)
                .font(.system(size: 12, weight: .bold))
        }
        .foregroundStyle(.white)
        .padding(.horizontal, Space.s3)
        .frame(height: 30)
        .background(
            active ? Color.tujiInk.opacity(0.64) : Color.tujiTeal,
            in: .capsule
        )
    }

    private var isOwnItem: Bool {
        guard case let .signedIn(user) = self.auth.state,
              let username = user.username,
              let handle = self.vm.item.author?.handle
        else { return false }
        return username.caseInsensitiveCompare(handle) == .orderedSame
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
