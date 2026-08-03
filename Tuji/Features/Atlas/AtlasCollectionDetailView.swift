// 公開合集詳情（MOJi 風格）：封面做主題化 header + 目錄 / 簡介 tab。
//
// 資料來源：GET /api/atlas/public/collections/{slug}。目錄裡的項目沿用 AtlasPublicTile，
// 點進去是既有的 AtlasPublicDetailView（逐張收藏 / 檢舉）；封面標頭也提供整個合集的收藏操作。

import Nuke
import NukeUI
import SwiftUI

private func collectionLearningPillTitle(remaining: Int, total: Int) -> String {
    if remaining == 0 { return tujiLocalized("全部學習中") }
    if remaining < total { return tujiLocalized("加入其餘 \(remaining) 個") }
    return tujiLocalized("全部加入學習")
}

struct AtlasCollectionDetailView: View {
    @Environment(AuthService.self) private var auth
    @Environment(CollectionBookmarkStore.self) private var bookmarks
    @Environment(DeepLinkCoordinator.self) private var deepLinks

    @State private var vm: CollectionDetailVM
    @State private var tab: Tab = .catalog
    @State private var selectedItem: AtlasPublicItem?
    @State private var selectedAuthorHandle: String?
    @State private var showSignInPrompt = false
    @State private var showUnsavePrompt = false
    @State private var showBookmarkErrorPrompt = false
    @State private var showLearnAllPrompt = false
    @State private var showLearningErrorPrompt = false

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
                } else if case .loading = self.vm.phase {
                    ProgressView()
                        .tint(.tujiTeal)
                        .padding(.top, Space.s12)
                } else {
                    self.errorState
                }
            }
            .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.tujiBg)
        .navigationTitle(self.vm.collection?.title ?? tujiLocalized("合集"))
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: self.$selectedItem) { item in
            AtlasPublicDetailView(item: item)
        }
        .navigationDestination(item: self.$selectedAuthorHandle) { handle in
            AtlasAuthorProfileView(handle: handle)
        }
        .task(id: self.loadKey) {
            await self.openCollection()
        }
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

    private func header(_ collection: AtlasCollection) -> some View {
        HStack(alignment: .top, spacing: Space.s4) {
            CollectionIdentityTile(
                collectionID: collection.id,
                avatarColor: collection.avatarColor,
                avatarImageURL: collection.avatarURL,
                size: 104
            )

            VStack(alignment: .leading, spacing: Space.s2) {
                Text(collection.title)
                    .font(.tujiH2)
                    .foregroundStyle(.tujiInk)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                if let author = collection.author {
                    Button {
                        self.selectedAuthorHandle = author.handle
                    } label: {
                        HStack(spacing: 6) {
                            ProfileAvatar(avatar: author.avatar, size: 22)
                            Text(author.displayName)
                                .font(.tujiCaption)
                                .foregroundStyle(.tujiInk2)
                                .lineLimit(1)
                        }
                    }
                    .buttonStyle(.plain)
                }
                HStack(spacing: Space.s2) {
                    Text(collection.langBadge)
                        .font(.system(size: 10, weight: .heavy))
                        .foregroundStyle(.tujiTeal)
                        .padding(.horizontal, Space.s2)
                        .frame(height: 22)
                        .background(.tujiTealSoft, in: .capsule)
                    self.stat(icon: "square.stack", title: "內容", value: collection.itemCount)
                    self.stat(icon: "bookmark", title: "收藏", value: collection.saveCount)
                }
                self.bookmarkPill
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(Space.s4)
        .background(.tujiCard, in: .rect(cornerRadius: Radius.lg))
        .overlay {
            RoundedRectangle(cornerRadius: Radius.lg)
                .stroke(.tujiInk4.opacity(0.22), lineWidth: 1)
        }
        .padding(.horizontal, Space.s6)
        .padding(.top, Space.s4)
    }

    private func stat(icon: String, title: LocalizedStringKey, value: Int) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon).font(.system(size: 11, weight: .bold))
            Text(title).font(.system(size: 12, weight: .semibold))
            Text("\(value)").font(.system(size: 12, weight: .heavy))
        }
        .foregroundStyle(.tujiInk3)
    }

    @ViewBuilder
    private var bookmarkPill: some View {
        if self.isOwnCollection {
            self.pillLabel(icon: nil, title: "你的合集")
        } else {
            Button(action: self.bookmarkTapped) {
                if self.vm.bookmarkBusy || (self.isSignedIn && !self.vm.bookmarkLoaded) {
                    ProgressView()
                        .controlSize(.small)
                        .tint(.tujiTeal)
                        .frame(minWidth: 88)
                } else {
                    self.pillLabel(
                        icon: self.vm.isSaved ? "bookmark.fill" : "bookmark",
                        title: self.vm.isSaved ? "已收藏" : "收藏合集"
                    )
                }
            }
            .buttonStyle(.plain)
            .disabled(self.vm.bookmarkBusy)
            .accessibilityLabel(self.vm.isSaved ? "已收藏" : "收藏合集")
        }
    }

    private func pillLabel(icon: String?, title: LocalizedStringKey) -> some View {
        HStack(spacing: 5) {
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .bold))
            }
            Text(title)
                .font(.system(size: 12, weight: .bold))
        }
        .foregroundStyle(.tujiTeal)
        .padding(.horizontal, Space.s3)
        .frame(height: 30)
        .frame(minWidth: 88)
        .background(.tujiTealSoft, in: .capsule)
    }

    private func bookmarkTapped() {
        guard self.isSignedIn else {
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
            isSignedIn: self.isSignedIn,
            username: self.signedInUser?.username,
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

    private var isSignedIn: Bool {
        self.signedInUser != nil
    }

    private var isOwnCollection: Bool {
        self.vm.isOwner
    }

    private var loadKey: String {
        "\(self.vm.slug)-\(self.signedInUser?.id.uuidString ?? "guest")"
    }

    // MARK: Tabs

    private var tabBar: some View {
        HStack(spacing: Space.s5) {
            self.tabButton("目錄", .catalog)
            self.tabButton("簡介", .about)
            Spacer()
            if self.tab == .catalog, self.vm.unlocked, self.vm.totalCount > 0 {
                self.learningPill
            }
        }
        .padding(.horizontal, Space.s6)
        .padding(.top, Space.s4)
        .padding(.bottom, Space.s2)
    }

    @ViewBuilder
    private var learningPill: some View {
        if self.vm.learningBusy {
            ProgressView()
                .controlSize(.small)
                .tint(.tujiTeal)
                .frame(minWidth: 98, minHeight: 30)
        } else {
            let remaining = self.vm.remainingLearningCount
            Button {
                self.showLearnAllPrompt = true
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: remaining == 0 ? "checkmark" : "plus")
                        .font(.system(size: 11, weight: .bold))
                    Text(collectionLearningPillTitle(
                        remaining: remaining,
                        total: self.vm.totalCount
                    ))
                    .font(.system(size: 12, weight: .bold))
                }
                .foregroundStyle(remaining == 0 ? .tujiInk3 : .tujiTeal)
                .padding(.horizontal, Space.s3)
                .frame(height: 30)
                .background(
                    remaining == 0 ? Color.tujiInk4.opacity(0.18) : Color.tujiTealSoft,
                    in: .capsule
                )
            }
            .buttonStyle(.plain)
            .disabled(remaining == 0)
        }
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
                VStack(spacing: 0) {
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
                                onOpen: {
                                    if self.vm.unlocked { self.selectedItem = item }
                                },
                                onOpenAuthor: self.vm.unlocked ? item.author.map { author in
                                    { self.selectedAuthorHandle = author.handle }
                                } : nil
                            )
                            .allowsHitTesting(self.vm.unlocked)
                        }
                    }
                    .padding(.horizontal, Space.s6)
                    if !self.vm.unlocked {
                        HStack(spacing: Space.s2) {
                            Image(systemName: "lock.fill")
                            Text("收藏合集後查看全部 \(self.vm.totalCount) 個內容")
                        }
                        .font(.tujiCaption)
                        .foregroundStyle(.tujiInk3)
                        .frame(maxWidth: .infinity)
                        .padding(.top, Space.s4)
                    }
                }
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
            Text(self.vm.isUnavailable
                ? tujiLocalized("找不到這個合集")
                : tujiLocalized("載入失敗，請稍後再試"))
                .font(.tujiBody)
                .foregroundStyle(.tujiInk3)
            BBtn(title: "重試", fullWidth: false) {
                Task { await self.openCollection() }
            }
        }
        .padding(.top, Space.s12)
    }
}
