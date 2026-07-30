// 公開圖鑑「作者主頁」（點公開項目的「by 作者」進來，或從 我的 看自己的那一份）。
//
// 資料來源：GET /api/atlas/public/authors/{handle} —— 作者身分 + 其已公開項目
// + 累計被收藏數（docs/COMMUNITY_ATLAS_PLAN.md §3B/§3C）。公開、吃 CDN 快取。
//
// 同一個畫面服務兩種讀者。`isSelf` 只加兩樣東西：頂部一條「這是別人看到的你」
// 橫幅，和一個直接開公開身分 sheet 的編輯入口——看到問題能當場改，迴圈是閉的。
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
        ScrollView {
            VStack(spacing: Space.s5) {
                if self.vm.isSelf {
                    self.previewBanner
                }
                if let author = self.vm.author {
                    self.headerCard(author)
                    if self.vm.showsSegmentedControl {
                        self.segmentPicker
                    }
                    switch self.vm.visibleSegment {
                    case .collections: self.collectionsSection
                    case .items: self.itemsSection
                    }
                } else if case .loading = self.vm.phase {
                    ProgressView()
                        .tint(.tujiTeal)
                        .padding(.top, Space.s12)
                } else {
                    self.blankState
                }
            }
            .padding(Space.s6)
        }
        .background(.tujiBg)
        .navigationTitle(self.vm.author?.displayName ?? self.vm.handle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if self.vm.isSelf {
                ToolbarItem(placement: .topBarTrailing) {
                    self.editButton
                }
            }
        }
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

    // MARK: Self-view chrome

    private var previewBanner: some View {
        HStack(spacing: Space.s2) {
            Image(systemName: "eye")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.tujiTeal)
            Text("這是別人看到的你")
                .font(.tujiCaption)
                .foregroundStyle(.tujiInk2)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Space.s4)
        .padding(.vertical, Space.s3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.tujiTealSoft, in: .rect(cornerRadius: Radius.md))
    }

    /// Pushes the profile editor rather than a sheet: 編輯個人資料 is now the
    /// single place the whole profile is edited, so the preview links to it
    /// instead of owning a second copy of the form.
    private var editButton: some View {
        Button {
            self.editing = true
        } label: {
            Text("編輯")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.tujiTeal)
        }
    }

    // MARK: Blank states

    /// Three different nothings, and they mean different things: the author has
    /// published nothing yet, no such author exists, or the request failed.
    @ViewBuilder
    private var blankState: some View {
        switch self.vm.phase {
        case .notFound where self.vm.isSelf:
            MascotEmptyState(
                pose: .think,
                title: "你還沒有公開任何圖鑑",
                message: "公開之後，這裡就是別人看到的你。"
            ) {
                NavigationLink(value: NavRoute.atlasManage) {
                    Text("去自製圖鑑")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, Space.s5)
                        .padding(.vertical, Space.s3)
                        .background(.tujiTeal, in: .capsule)
                }
                .buttonStyle(.plain)
            }
            .padding(.top, Space.s8)
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
                .foregroundStyle(.tujiInk4)
            Text(text)
                .font(.tujiBody)
                .foregroundStyle(.tujiInk3)
            if retry {
                BBtn(title: "重試", fullWidth: false) {
                    Task { await self.vm.load() }
                }
            }
        }
        .padding(.top, Space.s12)
    }

    // MARK: Header

    private func headerCard(_ author: AtlasAuthor) -> some View {
        VStack(spacing: Space.s3) {
            // The author's chosen mascot pose — the same avatar the rest of the
            // app shows them, so the public page is recognisably theirs.
            MascotAvatar(pose: MascotPose(rawValue: author.avatar) ?? .face, size: 84)

            VStack(spacing: 2) {
                Text(author.displayName)
                    .font(.tujiH2)
                    .foregroundStyle(.tujiInk)
                Text("@\(author.handle)")
                    .font(.tujiCaption)
                    .foregroundStyle(.tujiInk3)
            }

            if let bio = author.bio?.trimmingCharacters(in: .whitespacesAndNewlines),
               !bio.isEmpty
            {
                Text(bio)
                    .font(.tujiBody)
                    .foregroundStyle(.tujiInk2)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, Space.s1)
            }

            HStack(spacing: Space.s6) {
                self.stat(value: "\(author.publishedCount)", label: tujiLocalized("公開項目"))
                // The altruistic signal: how much this author's work has helped
                // others (docs/COMMUNITY_ATLAS_PLAN.md §3C).
                self.stat(value: "\(author.saveCount)", label: tujiLocalized("被收藏"))
                if let joined = author.joinedAt, !joined.isEmpty {
                    self.stat(value: String(joined.prefix(7)), label: tujiLocalized("加入"))
                }
            }
            .padding(.top, Space.s1)
        }
        .frame(maxWidth: .infinity)
        .padding(Space.s6)
        .background(.tujiCard)
        .clipShape(RoundedRectangle(cornerRadius: Radius.xl))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.xl)
                .stroke(.tujiInk4.opacity(0.2), lineWidth: 1)
        )
    }

    private func stat(value: String, label: String) -> some View {
        VStack(spacing: 1) {
            Text(value)
                .font(.system(size: 18, weight: .heavy))
                .foregroundStyle(.tujiInk)
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.tujiInk3)
        }
    }

    // MARK: Segments

    /// Only drawn when the author actually has collections — see
    /// `AuthorProfileVM.showsSegmentedControl`. An author with none gets exactly
    /// the page they had before: the language-grouped grid, no chrome.
    private var segmentPicker: some View {
        Picker("", selection: self.$vm.segment) {
            Text("合集").tag(AuthorProfileVM.Segment.collections)
            Text("圖鑑").tag(AuthorProfileVM.Segment.items)
        }
        .pickerStyle(.segmented)
        .labelsHidden()
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
        VStack(alignment: .leading, spacing: Space.s4) {
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
                    .font(.tujiCaption)
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
                    .font(.tujiOverline)
                    .tracking(2)
                    .foregroundStyle(.tujiInk3)
            }
            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: Space.s3),
                    GridItem(.flexible(), spacing: Space.s3)
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
