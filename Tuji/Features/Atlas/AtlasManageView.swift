// 「圖鑑管理」把使用者自製的卡片與合集收在同一個分頁式入口。卡片頁是
// list-based 查 + 刪：browse the cards you've made, open one for a read-only
// look, or delete it.
// Creating new cards lives in the camera quick-add flow (AtlasCaptureView);
// editing (改) is a future addition that needs a backend PATCH endpoint.
//
// Everything the shelf decides — the image→item join, the learning-direction
// filter, the loading/failed/empty/hidden state, the selection set, delete and
// 取消公開 — lives in AtlasShelfModel. These views are presentation only.

import NukeUI
import SwiftUI

enum AtlasManagementSection: Hashable {
    case cards
    case collections
}

struct AtlasManageView: View {
    @Environment(\.targetLanguage) private var targetLanguage

    @State private var shelf = AtlasShelfModel()
    @State private var section: AtlasManagementSection
    @State private var didVisitCollections: Bool
    @State private var showCreateCollection = false

    init(initialSection: AtlasManagementSection = .cards) {
        _section = State(initialValue: initialSection)
        _didVisitCollections = State(initialValue: initialSection == .collections)
    }

    /// The bar's one trailing action, and what it is depends on which pane is
    /// showing — selecting cards, or creating a collection.
    @ViewBuilder
    private var trailingAction: some View {
        switch self.section {
        case .cards:
            if self.shelf.canSelect {
                TujiNavTextAction(
                    title: self.shelf.isSelecting ? "完成" : "選取"
                ) {
                    self.shelf.setSelecting(!self.shelf.isSelecting)
                }
            }
        case .collections:
            TujiNavIcon(systemName: "plus", label: "建立合集") {
                self.showCreateCollection = true
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            TujiNavBar(leading: .back) {
                self.trailingAction
            }
            TujiScreenTitle("圖鑑管理")
            TujiSegmented(
                options: [
                    (AtlasManagementSection.cards, "圖鑑卡片"),
                    (AtlasManagementSection.collections, "合集")
                ],
                selection: self.$section
            )
            .padding(.vertical, Space.s3)
            .background(.tujiPaper)
            .accessibilityLabel(Text("管理內容"))

            ZStack {
                AtlasCardsManagementPane(shelf: self.shelf)
                    .opacity(self.section == .cards ? 1 : 0)
                    .allowsHitTesting(self.section == .cards)
                    .accessibilityHidden(self.section != .cards)

                if self.didVisitCollections {
                    AtlasMyCollectionsView(showCreate: self.$showCreateCollection)
                        .opacity(self.section == .collections ? 1 : 0)
                        .allowsHitTesting(self.section == .collections)
                        .accessibilityHidden(self.section != .collections)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(.tujiPaper)
        .navigationTitle("圖鑑管理")
        .toolbar(.hidden, for: .navigationBar)
        // 當前圖鑑語言 is an explicit model input, not something the shelf reaches
        // for. `initial: true` is the scoping act, not an optimisation — the
        // shelf shows nothing until this runs. Setting it re-scopes the rows and
        // drops any selection that just went off-screen.
        .onChange(of: self.targetLanguage, initial: true) { _, language in
            self.shelf.targetLanguage = language
        }
        .onChange(of: self.section) { previous, _ in
            if self.section == .collections {
                self.didVisitCollections = true
            }
            if previous == .cards {
                self.shelf.setSelecting(false)
            }
        }
    }
}

private struct AtlasCardsManagementPane: View {
    let shelf: AtlasShelfModel

    @Environment(\.targetLanguage) private var targetLanguage

    @State private var pendingDelete: AtlasShelfRow?
    @State private var showBatchDeleteConfirm = false

    /// 「英文圖鑑」/「日文圖鑑」 for the hidden-cards hint — the *other*
    /// direction, i.e. where the hidden cards live.
    private var otherDirectionTitle: String {
        self.targetLanguage == .ja ? LearningDirection.zhEn.title : LearningDirection.zhJa.title
    }

    var body: some View {
        // Capture the pending rows before the prompt runs its action: tujiPrompt
        // sets isPresented = false first (which nils the backing state), so
        // reading it inside the action is always empty — the "刪除沒反應" bug.
        let target = self.pendingDelete
        let batch = Array(self.shelf.selectedIds)
        return ScrollView {
            TujiSection(title: "我的圖鑑卡片") {
                if let errorMessage = self.shelf.errorMessage {
                    Text(errorMessage)
                        .font(.tujiBodySm)
                        .foregroundStyle(.tujiAlert)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, Space.s4)
                        .padding(.vertical, Space.s3)
                }
                switch self.shelf.state {
                case .loading:
                    TujiSkeletonRows(count: 4, height: 88)
                case .failed:
                    self.failedRow
                case let .hiddenElsewhere(count):
                    self.hiddenHintRow(count)
                case .empty:
                    self.emptyRow
                case .loaded:
                    ForEach(self.shelf.rows) { row in
                        self.imageRow(row)
                    }
                    if self.shelf.hiddenCount > 0 {
                        self.hiddenHintRow(self.shelf.hiddenCount)
                    }
                }
            }
            .padding(.bottom, Space.s6)
        }
        .background(.tujiPaper)
        .safeAreaInset(edge: .bottom) {
            if self.shelf.isSelecting, !self.shelf.selectedIds.isEmpty {
                self.deleteBar
            }
        }
        .task { await self.shelf.load() }
        .tujiPrompt(
            isPresented: Binding(
                get: { self.pendingDelete != nil },
                set: { if !$0 { self.pendingDelete = nil } }
            ),
            style: .destructive,
            title: "刪除這張卡片？",
            message: "圖片與它生成的卡片都會一起刪除，無法復原。",
            primary: TujiPromptAction("刪除", role: .destructive) {
                if let target { Task { await self.shelf.delete([target.id]) } }
            },
            secondary: TujiPromptAction("取消", role: .cancel) {}
        )
        .tujiPrompt(
            isPresented: self.$showBatchDeleteConfirm,
            style: .destructive,
            title: "刪除所選卡片？",
            message: "圖片與它們生成的卡片都會一起刪除，無法復原。",
            primary: TujiPromptAction("刪除", role: .destructive) {
                Task { await self.shelf.delete(batch) }
            },
            secondary: TujiPromptAction("取消", role: .cancel) {}
        )
        .tujiStatusToast(isPresented: self.shelf.deleting, style: .deleting)
    }

    /// One card row. In selection mode it's a tappable checkbox row; otherwise
    /// it keeps the push-to-detail + swipe-to-delete behaviour.
    @ViewBuilder
    private func imageRow(_ row: AtlasShelfRow) -> some View {
        if self.shelf.isSelecting {
            let selected = self.shelf.isSelected(row.id)
            Button {
                self.shelf.toggleSelection(row.id)
            } label: {
                HStack(spacing: 0) {
                    // Selection is a 3pt leading edge, not a circle — circles are
                    // the system's checkbox and the one shape this design keeps
                    // for things that "speak" (avatars, dots, the cat's bubble).
                    Rectangle()
                        .fill(selected ? Color.tujiCurrent : .clear)
                        .frame(width: Border.bw3)
                    self.rowBody(row)
                        .padding(.horizontal, Space.s4)
                }
                .background(selected ? Color.tujiPaper2 : .tujiPaper)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(selected ? [.isSelected] : [])
        } else {
            TujiSwipeRow(
                actionLabel: "刪除",
                systemImage: "trash",
                action: { self.pendingDelete = row }
            ) {
                NavigationLink {
                    AtlasManageDetailView(
                        shelf: self.shelf,
                        row: row,
                        onDelete: { self.pendingDelete = row }
                    )
                } label: {
                    self.rowBody(row)
                        .padding(.horizontal, Space.s4)
                }
                .tujiRowStyle()
            }
        }
    }

    private var deleteBar: some View {
        BBtn(
            title: "刪除 \(self.shelf.selectedIds.count) 張卡片",
            bg: .tujiAlert,
            fg: .tujiPaper,
            fullWidth: true,
            icon: "trash"
        ) {
            self.showBatchDeleteConfirm = true
        }
        .padding(.horizontal, Space.s4)
        .padding(.vertical, Space.s3)
        .background(.tujiPaper)
    }

    /// A failed sync used to fall through to 「還沒有卡片」, telling a user who
    /// owns cards that they own none.
    private var failedRow: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            // The sentence comes from `TujiBlankState`; the shape does not —
            // this one is a left-aligned row inside a list, not a centred shelf.
            Text(TujiBlankState.failedMessage)
                .font(.tujiLabel)
                .foregroundStyle(.tujiInk3)
            BBtn(title: "重試", fullWidth: false) {
                Task { await self.shelf.load() }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Space.s4)
        .padding(.vertical, Space.s3)
    }

    /// Shown whenever the direction filter is hiding cards, so a user who
    /// switched EN↔JA knows where their captures went (and that nothing was
    /// deleted).
    private func hiddenHintRow(_ count: Int) -> some View {
        // Deliberately not an empty state. "There is nothing here" and "your
        // things are on the other side" are different sentences, and confusing
        // them makes a user who switched EN↔JA think their cards were deleted.
        HStack(spacing: Space.s3) {
            Text("另有 \(count) 張卡片屬於\(self.otherDirectionTitle)")
                .font(.tujiBodySm)
                .foregroundStyle(.tujiInk2)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: Space.s2)
            Text("切換 →")
                .font(.tujiLabel)
                .tracking(0.5)
                .foregroundStyle(.tujiInk)
                .underline()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Space.s4)
        .frame(minHeight: 56)
        .background(.tujiPaper2)
    }

    private var emptyRow: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("還沒有自制圖鑑卡片")
                .font(.tujiBodySm(.strong))
                .foregroundStyle(.tujiInk)
            Text("點底下中間的相機，拍一張就能做卡片。")
                .font(.tujiLabel)
                .foregroundStyle(.tujiInk3)
        }
        .padding(.vertical, Space.s2)
    }

    private func rowBody(_ row: AtlasShelfRow) -> some View {
        HStack(spacing: Space.s3) {
            ZStack {
                Rectangle().fill(.tujiPaper)
                LazyImage(url: row.image.thumbURL) { state in
                    if let img = state.image {
                        img.resizable().aspectRatio(contentMode: .fill)
                    } else if state.error != nil {
                        Image(systemName: "photo").foregroundStyle(.tujiInk3)
                    } else {
                        TujiImagePlaceholder()
                    }
                }
            }
            .frame(width: 52, height: 52)
            .clipShape(RoundedRectangle(cornerRadius: Radius.r0))

            VStack(alignment: .leading, spacing: 2) {
                Text(row.title)
                    .font(.tujiBodySm(.strong))
                    .foregroundStyle(.tujiInk)
                    .lineLimit(1)
                if let subtitle = row.subtitle {
                    Text(subtitle)
                        .font(.tujiLabel)
                        .foregroundStyle(.tujiInk3)
                        .lineLimit(1)
                }
            }
            Spacer()
            Text(row.statusLabel)
                .font(.tujiLabel)
                .foregroundStyle(.tujiInk3)
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Read-only detail

private struct AtlasManageDetailView: View {
    let shelf: AtlasShelfModel
    /// The row rather than the image: 狀態 is the folded answer (an in-flight
    /// 生成佇列 job wins over the server's row), and deriving it a second time
    /// here is how this screen and the 卡片 grid came to disagree about one photo.
    let row: AtlasShelfRow
    let onDelete: () -> Void

    @State private var showWithdrawConfirm = false
    @Environment(\.dismiss) private var dismiss
    @Environment(CommunityFeedRefresh.self) private var feedRefresh

    private var image: AtlasImageSummary {
        self.row.image
    }

    private var item: AtlasItem? {
        self.row.item
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.s3) {
                ZStack {
                    Rectangle().fill(.tujiPaper)
                    LazyImage(url: self.image.imageURL) { state in
                        if let img = state.image {
                            img.resizable().aspectRatio(contentMode: .fit)
                        } else if state.error != nil {
                            Image(systemName: "photo")
                                .font(.tujiIcon(28, weight: .bold))
                                .foregroundStyle(.tujiInk3)
                        } else {
                            TujiImagePlaceholder()
                        }
                    }
                }
                .frame(height: 260)
                .clipShape(RoundedRectangle(cornerRadius: Radius.r0))

                if let item {
                    self.detailRow("圖片名稱", item.lemma)
                    self.detailRow("中文名稱", item.displayZhHant)
                    if let fine = item.fineLabel, !fine.isEmpty { self.detailRow("細分類", fine) }
                    if let pos = item.partOfSpeech, !pos.isEmpty { self.detailRow("詞性", pos) }
                    if let cat = item.category, !cat.isEmpty { self.detailRow("分類", cat) }
                } else {
                    Text("這張圖片還沒生成卡片。")
                        .font(.tujiBodySm)
                        .foregroundStyle(.tujiInk3)
                }
                self.detailRow("狀態", self.row.statusLabel)

                if let item {
                    self.publicationSection(item)
                }

                BBtn(title: "刪除這張卡片", bg: .tujiAlert, fg: .white, fullWidth: true, icon: "trash") {
                    self.onDelete()
                    self.dismiss()
                }
                .padding(.top, Space.s2)
            }
            .padding(.horizontal, Space.s4)
            .padding(.vertical, Space.s3)
        }
        .background(.tujiPaper)
        .navigationTitle(self.item?.lemma ?? tujiLocalized("圖片詳情"))
        .navigationBarTitleDisplayMode(.inline)
        .tujiPrompt(
            isPresented: self.$showWithdrawConfirm,
            style: .confirmation,
            title: "要取消公開嗎？",
            message: "這張卡片會從物見移除，你的卡片和學習紀錄都會保留。",
            detail: "之後隨時可以再公開一次。",
            primary: TujiPromptAction("取消公開") {
                self.withdraw()
            },
            secondary: TujiPromptAction("先不要", role: .cancel) {}
        )
    }

    // MARK: - 公開狀態

    /// Individual submission is intentionally absent. Private items enter
    /// review with their collection; existing public items can still be withdrawn.
    private func publicationSection(_ item: AtlasItem) -> some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            self.detailRow("公開狀態", item.review.label)

            if let errorMessage = self.shelf.errorMessage {
                Text(errorMessage)
                    .font(.tujiLabel)
                    .foregroundStyle(.tujiAlert)
            }

            // The counterpart to publishing. Without it the only way off the
            // wall is deleting the card — which also deletes this user's study
            // history and every saver's review progress.
            if item.review.canWithdraw {
                // Secondary, not destructive. Withdrawing is reversible and
                // carries no penalty — dressing it in red would make it read as
                // a punishment, and it is the opposite: it is the path that
                // *avoids* deleting a card, which would take every saver's
                // review progress with it.
                BBtn(
                    title: self.shelf.withdrawing ? "收回中…" : "取消公開",
                    bg: .tujiPaper2,
                    fg: .tujiInk,
                    fullWidth: true,
                    icon: "arrow.uturn.backward"
                ) {
                    self.showWithdrawConfirm = true
                }
                .disabled(self.shelf.withdrawing)
                .opacity(self.shelf.withdrawing ? 0.6 : 1)
            }
        }
        .padding(.top, Space.s2)
    }

    private func withdraw() {
        guard let item else { return }
        Task {
            // The View's only job here is to hand over the environment's feed
            // signal; what a withdrawal refreshes is AtlasMutationRefresh's call.
            let ok = await self.shelf.withdraw(
                itemId: item.id,
                refreshing: LiveAtlasMutationRefresher(feed: self.feedRefresh)
            )
            if ok {
                AnalyticsService.shared.track(.atlasPublishWithdrawn)
            }
        }
    }

    private func detailRow(_ title: LocalizedStringKey, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.tujiLabel)
                .foregroundStyle(.tujiInk3)
            Text(value)
                .font(.tujiBodySm(.strong))
                .foregroundStyle(.tujiInk)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

#Preview {
    NavigationStack {
        AtlasManageView()
            .environment(AuthService.shared)
            .environment(SettingsStore.shared)
            .environment(CommunityFeedRefresh())
    }
}
