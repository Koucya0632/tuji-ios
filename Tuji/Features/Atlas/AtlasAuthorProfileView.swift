// 公開圖鑑「作者主頁」（點公開項目的「by 作者」進來）。
//
// 資料來源：GET /api/atlas/public/authors/{username} —— 作者身分 + 其已公開項目
// + 累計被收藏數（docs/COMMUNITY_ATLAS_PLAN.md §3B/§3C）。公開、吃 CDN 快取。

import Nuke
import NukeUI
import SwiftUI

// MARK: - 作者主頁

struct AtlasAuthorProfileView: View {
    @State private var vm: AuthorProfileVM
    @State private var selectedItem: AtlasPublicItem?

    /// `username` is the attribution name shown on public items — the author's
    /// username on the server.
    init(username: String) {
        _vm = State(initialValue: AuthorProfileVM(username: username))
    }

    var body: some View {
        ScrollView {
            VStack(spacing: Space.s5) {
                if let author = self.vm.author {
                    self.headerCard(author)
                    self.itemsSection
                } else if case .loading = self.vm.phase {
                    ProgressView()
                        .tint(.tujiTeal)
                        .padding(.top, Space.s12)
                } else {
                    self.errorState
                }
            }
            .padding(Space.s6)
        }
        .background(.tujiBg)
        .navigationTitle(self.vm.author?.displayName ?? self.vm.username)
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: self.$selectedItem) { item in
            AtlasPublicDetailView(item: item)
        }
        // Analytics stays in the view (VMs don't reach AnalyticsService); track a
        // successful load once per author.
        .task(id: self.vm.username) {
            await self.vm.load()
            if case .ready = self.vm.phase {
                AnalyticsService.shared.track(.authorProfileViewed)
            }
        }
    }

    private var errorState: some View {
        VStack(spacing: Space.s3) {
            Image(systemName: "person.crop.circle.badge.questionmark")
                .font(.system(size: 40))
                .foregroundStyle(.tujiInk4)
            Text(self.vm.errorMessage == nil
                ? tujiLocalized("找不到這個作者")
                : tujiLocalized("載入失敗，請稍後再試"))
                .font(.tujiBody)
                .foregroundStyle(.tujiInk3)
            if self.vm.errorMessage != nil {
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
            ZStack {
                Circle().fill(.tujiTealSoft)
                Image(systemName: "person.crop.circle.fill")
                    .font(.system(size: 34, weight: .semibold))
                    .foregroundStyle(.tujiTeal)
            }
            .frame(width: 84, height: 84)

            VStack(spacing: 2) {
                Text(author.displayName)
                    .font(.tujiH2)
                    .foregroundStyle(.tujiInk)
                Text("@\(author.username)")
                    .font(.tujiCaption)
                    .foregroundStyle(.tujiInk3)
            }

            HStack(spacing: Space.s6) {
                self.stat(value: "\(author.publishedCount)", label: "公開項目")
                // The altruistic signal: how much this author's work has helped
                // others (docs/COMMUNITY_ATLAS_PLAN.md §3C).
                self.stat(value: "\(author.saveCount)", label: "被收藏")
                if let joined = author.joinedAt, !joined.isEmpty {
                    self.stat(value: String(joined.prefix(7)), label: "加入")
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

    // MARK: Items

    private var itemsSection: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            Text("公開的圖鑑")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(.tujiInk2)
                .frame(maxWidth: .infinity, alignment: .leading)

            if self.vm.items.isEmpty {
                Text("還沒有公開項目")
                    .font(.tujiCaption)
                    .foregroundStyle(.tujiInk3)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                LazyVGrid(
                    columns: [
                        GridItem(.flexible(), spacing: Space.s3),
                        GridItem(.flexible(), spacing: Space.s3)
                    ],
                    spacing: Space.s3
                ) {
                    ForEach(self.vm.items) { item in
                        AtlasPublicTile(item: item, onOpen: { self.selectedItem = item })
                    }
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
        AtlasAuthorProfileView(username: "mika_k")
    }
    .environment(SettingsStore.shared)
}
