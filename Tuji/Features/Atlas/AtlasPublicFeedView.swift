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
    /// The feed follows the user's current learning direction — Japanese learners
    /// see Japanese collections, English learners see English ones. There is no
    /// manual language switch on this screen, by product decision.
    @Environment(\.targetLanguage) private var targetLanguage
    @Environment(CommunityFeedRefresh.self) private var feedRefresh
    @Environment(TabNavigator.self) private var navigator
    @Environment(AuthService.self) private var auth
    @Environment(CollectionBookmarkStore.self) private var bookmarks
    @Environment(BlockStore.self) private var blocks

    @State private var browsing = PublicAtlasBrowsingModel()
    @State private var section: PublicAtlasBrowsingModel.Shelf = .explore
    @State private var savedShelfMounted = false

    var body: some View {
        VStack(spacing: 0) {
            // Guests have no public page, and an account with no UID yet has
            // nothing to link to — in both cases the row simply isn't there.
            if let uid = self.auth.uid {
                CommunityMyPageRow(uid: uid)
                Rectangle()
                    .fill(.tujiRule)
                    .frame(height: Border.bw1)
                    .padding(.leading, Space.s4)
                    .padding(.bottom, Space.s3)
            }
            self.segmentedControl
            self.content
        }
        // The 16pt every tab root opens with, now that nothing is drawn above
        // the first row of content.
        .padding(.top, Space.s3)
        .background(.tujiPaper)
        // Metadata only (VoiceOver, multitasking window title) — nothing draws
        // it, and the pushed collection detail hides its bar too, so not even a
        // back-button label borrows it. The title that used to head this screen
        // said what 探索/已收藏 and the collections themselves already say, and
        // it was the one title on a tab root with no controls beside it, so it
        // cost a full 73pt to repeat them.
        .navigationTitle("大家的物見")
        .toolbar(.hidden, for: .navigationBar)
        // Reconcile all product context through one state module. The view still
        // owns SwiftUI environment objects and translates them into plain values.
        .task(id: self.browsingLoadKey) {
            if self.section == .saved { self.savedShelfMounted = true }
            await self.blocks.loadIfNeeded()
            await self.browsing.update(
                shelf: self.section,
                language: self.targetLanguage,
                isSignedIn: !self.auth.isGuest,
                blockedAuthors: self.blocks.handles,
                pendingExploreRefresh: self.feedRefresh.consume()
            )
            if let identity = self.currentAuthorIdentity {
                self.browsing.applyAuthorIdentity(identity)
            }
        }
        .onChange(of: self.blocks.handles) { _, handles in
            self.browsing.applyBlocks(handles)
        }
        .onChange(of: self.currentAuthorIdentity) { _, identity in
            guard let identity else { return }
            self.browsing.applyAuthorIdentity(identity)
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

    // MARK: Content

    private var segmentedControl: some View {
        TujiSegmented(
            options: PublicAtlasBrowsingModel.Shelf.allCases.map {
                ($0, self.title(for: $0))
            },
            selection: self.$section
        )
        .padding(.bottom, Space.s3)
        .accessibilityLabel(Text("物見區段"))
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
                TujiImagePlaceholder()
                Text("載入中…")
                    .font(.tujiLabel)
                    .foregroundStyle(.tujiInk3)
                    .padding(.top, Space.s3)
                Spacer()
            }
            .frame(maxWidth: .infinity)
        } else {
            self.collectionShelf(self.browsing.explore, shelf: .explore) {
                self.emptyState
            }
        }
    }

    @ViewBuilder
    private var savedContent: some View {
        if self.auth.isGuest {
            VStack(spacing: Space.s3) {
                Spacer()
                Text("登入後才能查看已收藏的合集")
                    .font(.tujiBodySm)
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
            TujiProgressBar(progress: nil).frame(width: 56)
                .tint(.tujiCurrent)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            self.collectionShelf(self.browsing.saved, shelf: .saved) {
                TujiBlankState(
                    emptyText: self.savedEmptyText,
                    error: self.browsing.saved.errorMessage
                )
            }
        }
    }

    /// One shelf of 合集, drawn twice before this — 公開 and 已收藏 — as two
    /// ~30-line blocks whose diff was three keypaths and the blank state.
    ///
    /// The copy had already drifted: the empty case shares the `ScrollView` so
    /// that pull-to-refresh works when there is nothing to pull (which is
    /// exactly when a reader reaches for it), and that only works with the
    /// `containerRelativeFrame` giving the empty state something to fill. 公開
    /// had it; 已收藏, copied from it, did not.
    private func collectionShelf(
        _ state: PublicAtlasBrowsingModel.ShelfState,
        shelf: PublicAtlasBrowsingModel.Shelf,
        @ViewBuilder blank: () -> some View
    )
        -> some View
    {
        ScrollView {
            if state.collections.isEmpty {
                blank()
                    .containerRelativeFrame(.vertical)
            } else {
                LazyVStack(spacing: 0) {
                    ForEach(Array(state.collections.enumerated()), id: \.element.id) { index, collection in
                        if index > 0 {
                            Rectangle()
                                .fill(.tujiRule)
                                .frame(height: Border.bw1)
                                .padding(.horizontal, Space.s4)
                        }
                        AtlasCollectionCard(collection: collection) {
                            self.navigator.push(
                                .atlasCollectionDetail(
                                    slug: collection.slug, autoSave: false, preview: collection
                                )
                            )
                        }
                    }
                }
                .padding(.top, Space.s1)
                .padding(.bottom, Space.s5)
            }
        }
        // Allow the pull gesture even when the content is shorter than the viewport.
        .scrollBounceBehavior(.always, axes: .vertical)
        .refreshable {
            await self.browsing.refresh(
                shelf: shelf,
                language: self.targetLanguage,
                isSignedIn: !self.auth.isGuest
            )
        }
    }

    private var currentAuthorIdentity: AtlasAuthorRef? {
        guard let handle = self.auth.uid,
              case let .signedIn(user) = self.auth.state
        else { return nil }
        return AtlasAuthorRef(
            handle: handle,
            displayName: self.auth.displayName(fallback: handle),
            avatar: user.avatar ?? "face"
        )
    }

    private var browsingLoadKey: String {
        "\(self.section.rawValue)-\(self.targetLanguage.rawValue)-\(!self.auth.isGuest)"
    }

    private func title(for shelf: PublicAtlasBrowsingModel.Shelf) -> LocalizedStringKey {
        switch shelf {
        case .explore: "探索"
        case .saved: "已收藏"
        }
    }

    /// A `LocalizedStringKey` rather than a resolved `String`: it is handed to a
    /// `Text` inside this view, whose environment locale already follows uiLang.
    private var savedEmptyText: LocalizedStringKey {
        switch self.targetLanguage {
        case .ja: "目前沒有收藏的日文合集"
        case .en: "目前沒有收藏的英文合集"
        }
    }

    private var emptyState: some View {
        VStack(spacing: 0) {
            Spacer()
            TujiBlankState(
                icon: "square.stack.3d.up.slash",
                emptyText: "這個語言還沒有公開合集",
                error: self.browsing.explore.errorMessage,
                retry: {
                    await self.browsing.refresh(
                        shelf: .explore,
                        language: self.targetLanguage,
                        isSignedIn: !self.auth.isGuest
                    )
                },
                topPadding: 0
            )
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
                VStack(alignment: .leading, spacing: 2) {
                    Text(self.collection.title)
                        .font(.tujiH3)
                        .foregroundStyle(.tujiInk)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    // Nothing at all when the author has no confirmed public
                    // identity — the row must not fall back to a handle.
                    if self.showsAuthor, let author = self.collection.author {
                        Text(author.displayName)
                            .font(.tujiBodySm)
                            .foregroundStyle(.tujiInk2)
                            .lineLimit(1)
                    }
                    Text(self.counts)
                        .font(.tujiLabel)
                        .tracking(0.5)
                        .foregroundStyle(.tujiInk3)
                }
                Spacer(minLength: Space.s2)
                Text(self.collection.langBadge)
                    .font(.tujiLabel)
                    .tracking(0.5)
                    .foregroundStyle(.tujiInk2)
                    .padding(.horizontal, Space.s2)
                    .frame(height: 24)
                    .background(.tujiPaper2)
            }
            .padding(.horizontal, Space.s4)
            .padding(.vertical, Space.s3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(.rect)
        }
        .tujiRowStyle()
    }

    private var counts: String {
        let items = tujiLocalized("\(self.collection.itemCount) 字")
        guard self.collection.saveCount > 0 else { return items }
        return items + " · " + tujiLocalized("被收藏") + " \(self.collection.saveCount)"
    }

    private var cover: some View {
        CollectionIdentityTile(
            collectionID: self.collection.id,
            avatarColor: self.collection.avatarColor,
            avatarImageURL: self.collection.avatarURL,
            size: 56
        )
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
                Rectangle().fill(.tujiPaper)
                LazyImage(url: self.item.imageURL) { state in
                    if let image = state.image {
                        image.resizable().aspectRatio(contentMode: .fill)
                    } else if state.error != nil {
                        self.placeholder
                    } else {
                        TujiImagePlaceholder()
                    }
                }
                .pipeline(.shared)
            }
            .frame(height: 120)
            .clipped()
            .overlay(alignment: .topTrailing) {
                Text(self.item.langBadge)
                    .font(.tujiLabel)
                    .foregroundStyle(.tujiBrandSecondary)
                    .padding(.horizontal, Space.s2)
                    .padding(.vertical, 3)
                    .background(Color.tujiBrandSecondary.opacity(0.1), in: .rect(cornerRadius: Radius.r0))
                    .padding(Space.s2)
            }
            // 卡片主體點擊區（圖）→ 詳情
            .contentShape(Rectangle())
            .onTapGesture { self.onOpen() }

            VStack(alignment: .leading, spacing: 2) {
                Text(self.item.lemma)
                    .font(.tujiBodySm(.strong))
                    .foregroundStyle(.tujiInk)
                    .lineLimit(1)
                Text(self.item.displayZhHant)
                    .font(.tujiLabel)
                    .foregroundStyle(.tujiInk3)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                    .onTapGesture { self.onOpen() }
                if let author = self.item.author {
                    if let onOpenAuthor {
                        Button(action: onOpenAuthor) {
                            Text("by \(author.displayName)")
                                .font(.tujiLabel)
                                .foregroundStyle(.tujiBrandSecondary)
                                .lineLimit(1)
                                .padding(.top, 1)
                        }
                        .buttonStyle(.plain)
                    } else {
                        Text("by \(author.displayName)")
                            .font(.tujiLabel)
                            .foregroundStyle(.tujiInk3)
                            .lineLimit(1)
                            .padding(.top, 1)
                    }
                }
            }
            .padding(Space.s3)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(.tujiPaper)
        .clipShape(RoundedRectangle(cornerRadius: Radius.r0))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.r0)
                .stroke(.tujiRule.opacity(0.25), lineWidth: 1)
        )
    }

    private var placeholder: some View {
        ZStack {
            LinearGradient(
                colors: [.tujiBrandSecondary.opacity(0.1), .tujiPaper],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Image(systemName: "photo")
                .font(.tujiIcon(22))
                .foregroundStyle(.tujiInk3)
        }
    }
}

// MARK: - 詳情頁

struct AtlasPublicDetailView: View {
    @Environment(AuthService.self) private var auth
    @Environment(MasteryStore.self) private var mastery
    @Environment(TabNavigator.self) private var navigator
    @Environment(SettingsStore.self) private var settings
    @Environment(BlockStore.self) private var blocks
    @Environment(\.dismiss) private var dismiss
    @State private var vm: AtlasPublicDetailVM
    @State private var report = ReportFlow()
    @State private var showBlockPrompt = false
    @State private var showStopLearningPrompt = false
    // The author route is keyed by handle, never by display name — two people
    // may share a name, and only the handle is a valid path component.

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

    /// Blocking is keyed by the immutable TJ-UID, so an item whose author never
    /// resolved simply offers no block action rather than a broken one — and an
    /// item of your own offers none either, since blocking yourself would hide
    /// your own 圖鑑 from you.
    private var authorHandle: String? {
        guard let handle = self.vm.item.author?.handle, !handle.isEmpty else { return nil }
        guard !self.auth.isGuest, !self.auth.owns(handle: handle) else { return nil }
        return handle
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.s3) {
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
                        .font(.tujiLabel)
                        .foregroundStyle(.tujiAlert)
                        .frame(maxWidth: .infinity, alignment: .center)
                }

                Button {
                    self.report.begin(.item(slug: self.vm.item.slug))
                } label: {
                    Text(self.report.isSent ? "已收到檢舉" : "檢舉這個項目")
                        .font(.tujiLabel)
                        .foregroundStyle(self.report.isSent ? .tujiInk3 : .tujiAlert)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, Space.s2)
                }
                .buttonStyle(.plain)
                .disabled(self.report.isSent)

                // 檢舉 asks someone else to judge this one item; 封鎖 is the
                // reader's own decision about everything by this author. They
                // answer different needs, so they sit together.
                if let handle = self.authorHandle {
                    Button {
                        self.showBlockPrompt = true
                    } label: {
                        Text(self.blocks.isBlocked(handle) ? "已封鎖這位作者" : "封鎖這位作者")
                            .font(.tujiLabel)
                            .foregroundStyle(.tujiInk3)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, Space.s2)
                    }
                    .buttonStyle(.plain)
                    .disabled(self.blocks.isBlocked(handle))
                }
            }
            .padding(Space.s4)
        }
        .background(.tujiPaper)
        .navigationTitle(self.vm.item.lemma)
        .navigationBarTitleDisplayMode(.inline)
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
        .blockPrompt(
            handle: self.authorHandle,
            isPresented: self.$showBlockPrompt,
            onBlocked: { self.dismiss() }
        )
        .reportSheet(self.report)
    }

    private var imageCard: some View {
        ZStack {
            RoundedRectangle(cornerRadius: Radius.r0)
                .fill(.tujiPaper)
            LazyImage(url: self.vm.item.imageURL) { state in
                if let image = state.image {
                    image.resizable()
                        .aspectRatio(contentMode: .fit)
                        .padding(Space.s3)
                } else if state.error != nil {
                    Image(systemName: "photo")
                        .font(.tujiIcon(28))
                        .foregroundStyle(.tujiInk3)
                } else {
                    TujiImagePlaceholder()
                }
            }
            .pipeline(.shared)
        }
        .frame(height: 220)
        .frame(maxWidth: .infinity)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.r0)
                .stroke(.tujiRule.opacity(0.2), lineWidth: 1)
        )
    }

    private var previewTitle: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack(spacing: Space.s2) {
                Text(self.vm.item.lemma)
                    .font(.tujiH1)
                    .foregroundStyle(.tujiInk)
                Text(self.vm.item.langBadge)
                    .font(.tujiLabel)
                    .foregroundStyle(.tujiBrandSecondary)
                    .padding(.horizontal, Space.s2)
                    .padding(.vertical, 3)
                    .background(Color.tujiBrandSecondary.opacity(0.1), in: .rect(cornerRadius: Radius.r0))
            }
            Text(self.vm.item.displayZhHant)
                .font(.tujiBodySm)
                .foregroundStyle(.tujiInk2)
        }
    }

    private func titleRow(_ word: Word) -> some View {
        HStack(alignment: .top, spacing: Space.s3) {
            VStack(alignment: .leading, spacing: Space.s2) {
                TujiHeadword(word: word)
                HStack(spacing: Space.s2) {
                    TujiReadingLine(word: word)
                    if let partOfSpeech = word.partOfSpeech, !partOfSpeech.isEmpty {
                        Text(localizedPartOfSpeech(
                            partOfSpeech,
                            language: self.settings.current.uiLanguage
                        ))
                        .font(.tujiLabel)
                        .italic()
                        .foregroundStyle(.tujiInk3)
                    }
                    if let cefr = word.cefrLevel, !cefr.isEmpty {
                        Text(cefr)
                            .font(.tujiLabel)
                            .foregroundStyle(.tujiBrandSecondary)
                            .padding(.horizontal, Space.s2)
                            .padding(.vertical, 2)
                            .background(Color.tujiBrandSecondary.opacity(0.1), in: .rect(cornerRadius: Radius.r0))
                    }
                }
            }
            // See WordDetailView.titleRow: beside a `Spacer` the headword is
            // offered half the row unless it is prioritised.
            .layoutPriority(1)
            Spacer()
            PronunciationButton(
                text: word.word,
                language: word.taggedLanguage,
                audioUrls: word.audioUrls,
                size: 48
            )
        }
    }

    private var socialLearningRow: some View {
        HStack(spacing: Space.s2) {
            if let author = self.vm.item.author {
                Button {
                    self.navigator.push(.authorProfile(handle: author.handle, isSelf: false))
                } label: {
                    HStack(spacing: 6) {
                        ProfileAvatar(avatar: author.avatar, size: 24)
                        Text(author.displayName)
                            .font(.tujiLabel)
                            .foregroundStyle(.tujiBrandSecondary)
                            .lineLimit(1)
                    }
                }
                .buttonStyle(.plain)
            }

            Text("\(self.vm.saveCount ?? 0) 人學習中")
                .font(.tujiLabel)
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
                    .font(.tujiIcon(11, weight: .bold))
            }
            Text(title)
                .font(.tujiLabel)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, Space.s3)
        .frame(height: 30)
        .background(
            active ? Color.tujiInk.opacity(0.64) : Color.tujiAccumulation,
            in: .rect(cornerRadius: Radius.r0)
        )
    }

    private var isOwnItem: Bool {
        guard let handle = self.vm.item.author?.handle else { return false }
        return self.auth.owns(handle: handle)
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
    .environment(TabNavigator())
}
