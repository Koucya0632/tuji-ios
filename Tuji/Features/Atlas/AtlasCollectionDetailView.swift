// 公開合集詳情（MOJi 風格）：封面做主題化 header + 目錄 / 簡介 tab。
//
// 資料來源：GET /api/atlas/public/collections/{slug}。目錄裡的項目沿用 AtlasPublicTile，
// 點進去是既有的 AtlasPublicDetailView（逐張收藏 / 檢舉）；封面標頭也提供整個合集的收藏操作。

import Nuke
import NukeUI
import SwiftUI

/// The saved state is an ink-on-eye inversion like every other "this is the one
/// you picked" surface; unsaved is the plain primary button.
private struct CollectionSaveStyle: ButtonStyle {
    let saved: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(self.saved ? Color.tujiPaper : .tujiInk)
            .background(self.ground(pressed: configuration.isPressed))
            .animation(Motion.ease(Motion.d1), value: configuration.isPressed)
    }

    private func ground(pressed: Bool) -> Color {
        if self.saved { return pressed ? .tujiInk2 : .tujiPaper.opacity(0.2) }
        return pressed ? .tujiCurrentDeep : .tujiCurrent
    }
}

private func collectionLearningPillTitle(remaining: Int, total: Int) -> String {
    if remaining == 0 { return tujiLocalized("全部學習中") }
    if remaining < total { return tujiLocalized("加入其餘 \(remaining) 個") }
    return tujiLocalized("全部加入學習")
}

struct AtlasCollectionDetailView: View {
    @Environment(AuthService.self) private var auth
    @Environment(TabNavigator.self) private var navigator
    @Environment(CollectionBookmarkStore.self) private var bookmarks
    @Environment(DeepLinkCoordinator.self) private var deepLinks

    @State private var vm: CollectionDetailVM
    @State private var tab: Tab = .catalog
    @State private var showSignInPrompt = false
    @State private var showUnsavePrompt = false
    @State private var showBookmarkErrorPrompt = false
    @State private var showLearnAllPrompt = false
    @State private var showLearningErrorPrompt = false
    @State private var report = ReportFlow()

    private var reportButton: some View {
        Button {
            self.report.begin(.collection(slug: self.vm.slug))
        } label: {
            Text(self.report.isSent ? "已收到檢舉" : "檢舉這個合集")
                .font(.tujiLabel)
                .foregroundStyle(self.report.isSent ? .tujiInk3 : .tujiAlert)
                .frame(maxWidth: .infinity)
                .padding(.vertical, Space.s3)
        }
        .buttonStyle(.plain)
        .disabled(self.report.isSent)
        .padding(.top, Space.s4)
        .padding(.bottom, Space.s6)
    }

    private let autoSave: Bool

    enum Tab: Hashable { case catalog, about }

    /// `preview` is the card data from the feed, so the header renders instantly
    /// while the member items load.
    init(slug: String, preview: AtlasCollection? = nil, autoSave: Bool = false) {
        _vm = State(initialValue: CollectionDetailVM(slug: slug, preview: preview))
        self.autoSave = autoSave
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                if let collection = self.vm.collection {
                    self.header(collection)
                    self.tabBar
                    self.tabContent(collection)
                    // The 合集's own title / 簡介 / 頭像 are public UGC that the
                    // per-item 檢舉 inside it can't reach.
                    if !self.vm.isOwner {
                        self.reportButton
                    }
                } else if case .loading = self.vm.phase {
                    TujiPageLoading()
                } else {
                    self.errorState
                }
            }
            .frame(maxWidth: .infinity)
        }
        // Floats over the bleeding cover so the page opens with the photograph.
        .overlay(alignment: .topLeading) { TujiNavBar(leading: .back) }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.tujiPaper)
        .navigationTitle(self.vm.collection?.title ?? tujiLocalized("合集"))
        .toolbar(.hidden, for: .navigationBar)
        .task(id: self.loadKey) {
            await self.openCollection()
        }
        .reportSheet(self.report)
        .tujiPrompt(
            isPresented: self.$showSignInPrompt,
            style: .confirmation,
            title: "登入後才能收藏合集",
            primary: TujiPromptAction("登入") {
                self.deepLinks.receive(.collection(slug: self.vm.slug, autoSave: true))
                self.auth.exitGuestMode()
            },
            secondary: TujiPromptAction("取消", role: .cancel) {}
        )
        .tujiPrompt(
            isPresented: self.$showUnsavePrompt,
            style: .confirmation,
            title: "取消收藏這個合集？",
            primary: TujiPromptAction("確定", role: .destructive) {
                Task { await self.unsaveCollection() }
            },
            secondary: TujiPromptAction("取消", role: .cancel) {}
        )
        .tujiPrompt(
            isPresented: self.$showBookmarkErrorPrompt,
            style: .error,
            title: "操作失敗",
            message: "請稍後再試一次。",
            primary: TujiPromptAction("確定") {
                self.vm.dismissBookmarkActionError()
            }
        )
        .tujiPrompt(
            isPresented: self.$showLearnAllPrompt,
            style: .confirmation,
            title: "將這 \(self.vm.remainingLearningCount) 個單詞加入學習？",
            primary: TujiPromptAction("全部加入") {
                Task {
                    if await !(self.vm.learnRemaining()) {
                        self.showLearningErrorPrompt = self.vm.learningActionError != nil
                    }
                }
            },
            secondary: TujiPromptAction("取消", role: .cancel) {}
        )
        .tujiPrompt(
            isPresented: self.$showLearningErrorPrompt,
            style: .error,
            title: "加入失敗",
            message: self.vm.learningActionError.map { LocalizedStringKey($0) },
            primary: TujiPromptAction("確定") {
                self.vm.dismissLearningActionError()
            }
        )
    }

    // MARK: Header

    /// Cover, then a full-width ink action bar. This is the screen §4 named as
    /// "clean turned into empty": one white card holding an avatar, a title,
    /// four small statistics and a pale teal button, then half a screen of
    /// nothing. Every element was small and none of them was the point.
    ///
    /// A collection is made of photographs somebody took, which is the most
    /// persuasive thing about it — so the cover becomes the first event at full
    /// width, and the numbers and the action collect into one ink bar that acts
    /// as the screen's centre of gravity.
    private func header(_ collection: AtlasCollection) -> some View {
        VStack(spacing: 0) {
            self.cover(collection)
            self.actionBar(collection)
        }
    }

    private func cover(_ collection: AtlasCollection) -> some View {
        ZStack(alignment: .bottomLeading) {
            CollectionIdentityTile(
                collectionID: collection.id,
                avatarColor: collection.avatarColor,
                avatarImageURL: collection.avatarURL,
                size: nil
            )

            // One-way scrim: legibility, not decoration.
            LinearGradient(
                colors: [.clear, Color.tujiInk.opacity(0.7)],
                startPoint: .top,
                endPoint: .bottom
            )

            VStack(alignment: .leading, spacing: Space.s2) {
                Text(collection.title)
                    .font(.tujiH1)
                    .foregroundStyle(.tujiPaper)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                HStack(spacing: Space.s2) {
                    if let author = collection.author {
                        Button {
                            self.navigator.push(.authorProfile(handle: author.handle, isSelf: false))
                        } label: {
                            HStack(spacing: 6) {
                                ProfileAvatar(avatar: author.avatar, size: 24)
                                Text(author.displayName)
                                    .font(.tujiBodySm)
                                    .foregroundStyle(.tujiPaper.opacity(0.8))
                                    .lineLimit(1)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                    Text(collection.langBadge)
                        .font(.tujiLabel)
                        .tracking(0.5)
                        .foregroundStyle(.tujiPaper)
                        .padding(.horizontal, Space.s2)
                        .frame(height: 22)
                        .background(.tujiPaper.opacity(0.2))
                }
            }
            .padding(Space.s4)
        }
        .frame(maxWidth: .infinity)
        .aspectRatio(4.0 / 3.0, contentMode: .fill)
        .clipped()
    }

    private func actionBar(_ collection: AtlasCollection) -> some View {
        HStack(spacing: Space.s5) {
            self.stat(title: "內容", value: collection.itemCount)
            self.stat(title: "被收藏", value: collection.saveCount)
            Spacer(minLength: Space.s3)
            self.bookmarkAction
        }
        .padding(.horizontal, Space.s4)
        .frame(height: 72)
        .frame(maxWidth: .infinity)
        .background(.tujiInk)
    }

    private func stat(title: LocalizedStringKey, value: Int) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(value)")
                .font(.tujiMono)
                .foregroundStyle(.tujiPaper)
            Text(title)
                .font(.tujiLabel)
                .tracking(0.5)
                .foregroundStyle(.tujiPaper.opacity(0.6))
                .lineLimit(1)
                .fixedSize()
        }
    }

    @ViewBuilder
    private var bookmarkAction: some View {
        if self.isOwnCollection {
            Text("你的合集")
                .font(.tujiLabel)
                .tracking(0.5)
                .foregroundStyle(.tujiPaper.opacity(0.6))
        } else {
            Button(action: self.bookmarkTapped) {
                Group {
                    if self.vm.bookmarkBusy || (!self.auth.isGuest && !self.vm.bookmarkLoaded) {
                        TujiProgressBar(
                            progress: nil,
                            track: .tujiPaper.opacity(0.2),
                            fill: .tujiCurrent
                        )
                        .frame(width: 56)
                    } else {
                        // 「收藏」, not 「收進圖鑑」. Saving a collection unlocks
                        // browsing and counts toward the author's total — it puts
                        // nothing in your atlas. That is a separate, later action
                        // (「全部收進圖鑑」), and naming this one after it would be
                        // a button that lies. See CONTEXT.md.
                        Text(self.vm.isSaved ? "已收藏" : "收藏")
                            .font(.tujiH3)
                    }
                }
                .frame(minWidth: 96)
                .frame(height: 44)
                .padding(.horizontal, Space.s3)
            }
            .buttonStyle(CollectionSaveStyle(saved: self.vm.isSaved))
            .disabled(self.vm.bookmarkBusy)
            .accessibilityLabel(self.vm.isSaved ? "已收藏" : "收藏")
            .accessibilityAddTraits(self.vm.isSaved ? [.isSelected] : [])
        }
    }

    private func bookmarkTapped() {
        guard !self.auth.isGuest else {
            self.showSignInPrompt = true
            return
        }
        if self.vm.isSaved {
            self.showUnsavePrompt = true
        } else {
            Task { await self.saveCollection() }
        }
    }

    private func saveCollection() async {
        if let change = await self.vm.save() {
            self.publish(change)
        } else if self.vm.bookmarkActionError != nil {
            self.showBookmarkErrorPrompt = true
        }
    }

    private func openCollection() async {
        let change = await self.vm.open(context: .init(
            isSignedIn: !self.auth.isGuest,
            username: self.auth.uid,
            autoSave: self.autoSave
        ))
        if let change {
            self.publish(change)
        } else if self.vm.bookmarkActionError != nil {
            self.showBookmarkErrorPrompt = true
        }
    }

    private func unsaveCollection() async {
        if let change = await self.vm.unsave() {
            self.publish(change)
        } else if self.vm.bookmarkActionError != nil {
            self.showBookmarkErrorPrompt = true
        }
    }

    private func publish(_ change: CollectionDetailVM.BookmarkChange) {
        self.bookmarks.publish(
            collection: change.collection,
            saved: change.isSaved
        )
    }

    private var signedInUser: SessionUser? {
        if case let .signedIn(user) = self.auth.state { return user }
        return nil
    }

    private var isOwnCollection: Bool {
        self.vm.isOwner
    }

    private var loadKey: String {
        "\(self.vm.slug)-\(self.signedInUser?.id.uuidString ?? "guest")"
    }

    // MARK: Tabs

    private var tabBar: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            TujiSegmented(
                options: [(Tab.catalog, "目錄"), (Tab.about, "簡介")],
                selection: self.$tab
            )
            if self.tab == .catalog, self.vm.unlocked, self.vm.totalCount > 0 {
                self.learningPill.padding(.horizontal, Space.s4)
            }
        }
        .padding(.top, Space.s4)
        .padding(.bottom, Space.s2)
    }

    @ViewBuilder
    private var learningPill: some View {
        if self.vm.learningBusy {
            TujiProgressBar(progress: nil).frame(width: 56)
                .controlSize(.small)
                .tint(.tujiCurrent)
                .frame(minWidth: 98, minHeight: 30)
        } else {
            let remaining = self.vm.remainingLearningCount
            Button {
                self.showLearnAllPrompt = true
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: remaining == 0 ? "checkmark" : "plus")
                        .font(.tujiIcon(11, weight: .bold))
                    Text(collectionLearningPillTitle(
                        remaining: remaining,
                        total: self.vm.totalCount
                    ))
                    .font(.tujiLabel)
                }
                .foregroundStyle(remaining == 0 ? .tujiInk3 : .tujiAccumulation)
                .padding(.horizontal, Space.s3)
                .frame(height: 30)
                .background(
                    remaining == 0 ? Color.tujiPaper3 : Color.tujiAccumulationSoft,
                    in: .rect(cornerRadius: Radius.r0)
                )
            }
            .buttonStyle(.plain)
            .disabled(remaining == 0)
        }
    }

    @ViewBuilder
    private func tabContent(_ collection: AtlasCollection) -> some View {
        switch self.tab {
        case .catalog:
            if self.vm.items.isEmpty, case .loading = self.vm.phase {
                TujiPageLoading()
            } else if self.vm.items.isEmpty {
                Text("這個合集還沒有項目")
                    .font(.tujiBodySm)
                    .foregroundStyle(.tujiInk3)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Space.s5)
            } else {
                VStack(spacing: 0) {
                    LazyVGrid(
                        columns: [
                            GridItem(.flexible(), spacing: Space.s3, alignment: .top),
                            GridItem(.flexible(), spacing: Space.s3, alignment: .top)
                        ],
                        spacing: Space.s3
                    ) {
                        ForEach(self.vm.items) { item in
                            AtlasPublicTile(
                                item: item,
                                onOpen: {
                                    if self.vm.unlocked { self.navigator.push(.atlasPublicItem(item: item)) }
                                },
                                onOpenAuthor: self.vm.unlocked ? item.author.map { author in
                                    { self.navigator.push(.authorProfile(handle: author.handle, isSelf: false)) }
                                } : nil
                            )
                            .allowsHitTesting(self.vm.unlocked)
                        }
                    }
                    .padding(.horizontal, Space.s4)
                    if !self.vm.unlocked {
                        HStack(spacing: Space.s2) {
                            Image(systemName: "lock.fill")
                            Text("收藏合集後查看全部 \(self.vm.totalCount) 個內容")
                        }
                        .font(.tujiLabel)
                        .foregroundStyle(.tujiInk3)
                        .frame(maxWidth: .infinity)
                        .padding(.top, Space.s3)
                    }
                }
                .padding(.bottom, Space.s5)
            }
        case .about:
            let about = collection.description.flatMap { $0.isEmpty ? nil : $0 }
            Text(about ?? tujiLocalized("作者還沒有填寫簡介。"))
                .font(.tujiBodySm)
                .foregroundStyle(about == nil ? .tujiInk3 : .tujiInk2)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, Space.s4)
                .padding(.top, Space.s2)
                .padding(.bottom, Space.s5)
        }
    }

    private var errorState: some View {
        VStack(spacing: Space.s3) {
            Image(systemName: "square.stack.3d.up.slash")
                .font(.tujiIcon(40))
                .foregroundStyle(.tujiInk3)
            Text(self.vm.isUnavailable
                ? tujiLocalized("找不到這個合集")
                : tujiLocalized("載入失敗，請稍後再試"))
                .font(.tujiBodySm)
                .foregroundStyle(.tujiInk3)
            BBtn(title: "重試", fullWidth: false) {
                Task { await self.openCollection() }
            }
        }
        .padding(.top, Space.s5)
    }
}
