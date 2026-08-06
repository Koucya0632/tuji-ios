// 公開圖鑑「作者主頁」（點公開項目的「by 作者」進來，或從 我的 看自己的那一份）。
//
// 資料來源：GET /api/atlas/public/authors/{handle} —— 作者身分 + 其已公開項目
// + 累計被收藏數（../docs/COMMUNITY_ATLAS_PLAN.md §3B/§3C — FEATURES.md §12.5）。
// 公開、吃 CDN 快取。
//
// 同一個畫面服務兩種讀者。`isSelf` 只加一個直接開公開身分 sheet 的編輯入口
// ——看到問題能當場改，迴圈是閉的。
// 其餘完全一致，因為這頁的價值就在於它就是別人看到的那一頁。

import Nuke
import NukeUI
import SwiftUI

// MARK: - 作者主頁

struct AtlasAuthorProfileView: View {
    @State private var vm: AuthorProfileVM
    @State private var selectedItem: AtlasPublicItem?
    @State private var selectedCollection: AtlasCollection?
    @State private var editing = false
    /// `handle` is the author's public handle (`profiles.username`) — the link
    /// target carried on public items, never the name shown on them.
    init(handle: String, isSelf: Bool = false) {
        _vm = State(initialValue: AuthorProfileVM(handle: handle, isSelf: isSelf))
    }

    var body: some View {
        VStack(spacing: 0) {
            TujiNavBar(leading: .back) {
                if self.vm.isSelf { self.editButton }
            }
            self.scroll
        }
        .background(.tujiPaper)
        .navigationTitle(self.vm.author?.displayName ?? self.vm.handle)
        .toolbar(.hidden, for: .navigationBar)
        .navigationDestination(item: self.$selectedItem) { item in
            AtlasPublicDetailView(item: item)
        }
        .navigationDestination(item: self.$selectedCollection) { collection in
            AtlasCollectionDetailView(slug: collection.slug, preview: collection)
        }
        // Refetch on the way back: the page renders the very fields that screen
        // edits, and `isSelf` makes the reload bypass both caches.
        .navigationDestination(isPresented: self.$editing) {
            EditProfileView()
                .onDisappear { Task { await self.vm.load() } }
        }
        // Analytics stays in the view (VMs don't reach AnalyticsService); track a
        // successful load once per author. Looking at your own page is not a
        // community view, so it isn't counted.
        .task(id: self.vm.handle) {
            await self.vm.load()
            if case .ready = self.vm.phase, !self.vm.isSelf {
                AnalyticsService.shared.track(.authorProfileViewed)
            }
        }
    }

    private var scroll: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.s4) {
                if let author = self.vm.author {
                    self.headerCard(author)
                    // A synthesized header (own page, nothing published yet) has
                    // no segments to show — the counts above already say zero, so
                    // what is useful here is the way out.
                    if case .notFound = self.vm.phase {
                        self.nothingPublishedYet
                    } else {
                        if self.vm.showsSegmentedControl {
                            self.segmentPicker
                        }
                        switch self.vm.visibleSegment {
                        case .collections: self.collectionsSection
                        case .items: self.itemsSection
                        }
                    }
                } else if case .loading = self.vm.phase {
                    TujiPageLoading()
                } else {
                    self.blankState.padding(Space.s4)
                }
            }
            .padding(.bottom, Space.s6)
        }
    }

    // MARK: Self-view chrome

    /// Pushes the profile editor rather than a sheet: 編輯個人資料 is now the
    /// single place the whole profile is edited, so the preview links to it
    /// instead of owning a second copy of the form.
    private var editButton: some View {
        TujiNavTextAction(title: "編輯") { self.editing = true }
    }

    // MARK: Blank states

    /// Three different nothings, and they mean different things: the author has
    /// published nothing yet, no such author exists, or the request failed.
    /// Own page, nothing published. Shown under the header so the title states
    /// the situation without adding another authoring shortcut.
    private var nothingPublishedYet: some View {
        MascotEmptyState(
            pose: .think,
            title: "你還沒有公開任何圖鑑",
            message: "公開之後，這裡就是別人看到的你。"
        )
        .padding(.top, Space.s3)
    }

    @ViewBuilder
    private var blankState: some View {
        switch self.vm.phase {
        // Own page AND the identity fetch also failed — offline, most likely.
        // Falls back to the same card without a header above it.
        case .notFound where self.vm.isSelf:
            self.nothingPublishedYet
                .padding(.top, Space.s5)
        case .notFound:
            self.plainBlank(
                icon: "person.crop.circle.badge.questionmark",
                text: tujiLocalized("找不到這個作者"),
                retry: false
            )
        default:
            self.plainBlank(
                icon: "person.crop.circle.badge.exclamationmark",
                text: tujiLocalized("載入失敗，請稍後再試"),
                retry: true
            )
        }
    }

    private func plainBlank(icon: String, text: String, retry: Bool) -> some View {
        VStack(spacing: Space.s3) {
            Image(systemName: icon)
                .font(.system(size: 40))
                .foregroundStyle(.tujiInk3)
            Text(text)
                .font(.tujiBodySm)
                .foregroundStyle(.tujiInk3)
            if retry {
                BBtn(title: "重試", fullWidth: false) {
                    Task { await self.vm.load() }
                }
            }
        }
        .padding(.top, Space.s5)
    }

    // MARK: Header

    /// A full-bleed ink block rather than a white card. This page is about *a
    /// person*, and the block gives it the weight that says so — it also mirrors
    /// the ink block on 今天: one is "you", this one is "them".
    private func headerCard(_ author: AtlasAuthor) -> some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            HStack(alignment: .top, spacing: Space.s3) {
                ProfileAvatar(avatar: author.avatar, size: 72)
                VStack(alignment: .leading, spacing: 2) {
                    Text(author.displayName)
                        .font(.tujiH2)
                        .foregroundStyle(.tujiPaper)
                    // "UID: " rather than "@": the @ form promises a handle you
                    // could type or mention, and this is a machine-assigned code
                    // nobody ever types.
                    Text(verbatim: "\(tujiLocalized("UID")): \(author.handle)")
                        .font(.tujiMono)
                        .foregroundStyle(.tujiPaper.opacity(0.6))
                }
                Spacer(minLength: 0)
            }

            if let bio = author.bio?.trimmingCharacters(in: .whitespacesAndNewlines),
               !bio.isEmpty
            {
                Text(bio)
                    .font(.tujiBody)
                    .foregroundStyle(.tujiPaper.opacity(0.8))
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: Space.s5) {
                self.stat(value: "\(author.publishedCount)", label: tujiLocalized("公開項目"))
                // The altruistic signal: how much this author's work has helped
                // others (../docs/COMMUNITY_ATLAS_PLAN.md §3C — FEATURES.md §12.5).
                self.stat(value: "\(author.saveCount)", label: tujiLocalized("被收藏"))
            }
            .padding(.top, Space.s1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Space.s4)
        .background(.tujiInk)
    }

    private func stat(value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(verbatim: value)
                .font(.tujiMono)
                .foregroundStyle(.tujiPaper)
            Text(verbatim: label)
                .font(.tujiLabel)
                .tracking(0.5)
                .foregroundStyle(.tujiPaper.opacity(0.6))
                .lineLimit(1)
                .fixedSize()
        }
    }

    // MARK: Segments

    /// Only drawn when the author actually has collections — see
    /// `AuthorProfileVM.showsSegmentedControl`. An author with none gets exactly
    /// the page they had before: the language-grouped grid, no chrome.
    private var segmentPicker: some View {
        TujiSegmented(
            options: [
                (AuthorProfileVM.Segment.collections, "合集"),
                (AuthorProfileVM.Segment.items, "圖鑑")
            ],
            selection: self.$vm.segment
        )
    }

    // MARK: Collections

    /// Not language-scoped, matching the items below and the server query. The
    /// per-card language badge does the separating, since collections are far
    /// fewer than items and per-language headings would be mostly one-row.
    private var collectionsSection: some View {
        LazyVStack(spacing: Space.s3) {
            ForEach(self.vm.collections) { collection in
                AtlasCollectionCard(
                    collection: collection,
                    onOpen: { self.selectedCollection = collection },
                    showsAuthor: false
                )
            }
        }
    }

    // MARK: Items

    private var itemsSection: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            // The heading is redundant once the segmented control is naming the
            // section directly above it.
            if !self.vm.showsSegmentedControl {
                Text("公開的圖鑑")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.tujiInk2)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            if self.vm.groups.isEmpty {
                Text(self.vm.isSelf ? "你還沒有公開任何圖鑑" : "還沒有公開項目")
                    .font(.tujiLabel)
                    .foregroundStyle(.tujiInk3)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                ForEach(self.vm.groups) { group in
                    self.languageGroup(group)
                }
            }
        }
    }

    /// One language's items. The heading is dropped when the author only ever
    /// published in one language — labelling a single group explains nothing.
    private func languageGroup(_ group: AuthorProfileVM.LanguageGroup) -> some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            if self.vm.groups.count > 1 {
                // verbatim: both halves are already resolved (the label through
                // tujiLocalized, the count a number), so this must not become a
                // "%@ (%lld)" catalog key.
                Text(verbatim: "\(group.language.label) (\(group.count))")
                    .font(.tujiLabel)
                    .tracking(2)
                    .foregroundStyle(.tujiInk3)
            }
            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: Space.s3, alignment: .top),
                    GridItem(.flexible(), spacing: Space.s3, alignment: .top)
                ],
                spacing: Space.s3
            ) {
                ForEach(group.items) { item in
                    AtlasPublicTile(item: item, onOpen: { self.selectedItem = item })
                }
            }
        }
    }
}

// MARK: - Preview

// Hits the live endpoint; shows the not-found state without a signed-in
// backend, which is the state worth eyeballing anyway.
#Preview("作者主頁") {
    NavigationStack {
        AtlasAuthorProfileView(handle: "mika_k")
    }
    .environment(SettingsStore.shared)
}

#Preview("自己的主頁") {
    NavigationStack {
        AtlasAuthorProfileView(handle: "mika_k", isSelf: true)
    }
    .environment(SettingsStore.shared)
}
