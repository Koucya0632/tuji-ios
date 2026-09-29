// One 個人詞表: study it, look through it, trim it.

import NukeUI
import SwiftUI

struct WordListDetailView: View {
    @Environment(WordListsStore.self) private var store
    @Environment(WordsStore.self) private var words
    @Environment(SettingsStore.self) private var settings
    @Environment(\.dismiss) private var dismiss
    @State private var model: WordListDetailModel
    @State private var editing = false
    @State private var showRename = false
    @State private var confirmDelete = false
    @Environment(\.presentPaywall) private var presentPaywall
    @State private var failure: String?

    init(listId: String, repository: WordListRepository = LiveWordListRepository.shared) {
        self._model = State(initialValue: WordListDetailModel(listId: listId, repository: repository))
    }

    var body: some View {
        VStack(spacing: 0) {
            TujiNavBar(leading: .back) {
                if !self.model.wordIds.isEmpty {
                    TujiNavTextAction(title: self.editing ? "完成" : "編輯") { self.editing.toggle() }
                }
                Menu {
                    if !self.model.isReadOnly {
                        Button("重新命名") { self.showRename = true }
                    }
                    Button("刪除詞表", role: .destructive) { self.confirmDelete = true }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.tujiIcon(19, weight: .semibold))
                        .foregroundStyle(.tujiInk)
                        .frame(width: 44, height: 48)
                        .contentShape(.rect)
                }
                .accessibilityLabel(Text("更多"))
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    self.content
                }
                .padding(.bottom, Space.s6)
            }
        }
        .background(.tujiPaper)
        .navigationTitle(Text(verbatim: self.model.name))
        .toolbar(.hidden, for: .navigationBar)
        .task {
            await self.words.loadIfNeeded()
            await self.model.load()
        }
        .refreshable { await self.model.load() }
        .onChange(of: self.model.missing) { _, missing in
            if missing { self.dismiss() }
        }
        .sheet(isPresented: self.$showRename) {
            WordListNameSheet(title: "重新命名", actionTitle: "儲存", initialName: self.model.name) { name in
                await self.rename(name)
            }
            .paywallHost()
        }
        .tujiPrompt(
            isPresented: self.$confirmDelete,
            style: .destructive,
            title: "刪除這個詞表？",
            message: "只會刪除詞表，字的學習進度不受影響。",
            primary: TujiPromptAction("刪除", role: .destructive) {
                Task { await self.delete() }
            },
            secondary: TujiPromptAction("取消", role: .cancel) {}
        )
        .tujiPrompt(
            isPresented: Binding(get: { self.failure != nil }, set: { if !$0 { self.failure = nil } }),
            style: .error,
            title: "無法完成",
            message: "\(self.failure ?? "")",
            primary: TujiPromptAction("知道了") {}
        )
    }

    @ViewBuilder
    private var content: some View {
        switch self.model.phase {
        case .idle, .loading:
            TujiPageLoading()
                .frame(maxWidth: .infinity)
                .padding(.top, Space.s6)
        case .failed:
            TujiBlankState(kind: .failed, retry: { await self.model.load() })
        case .loaded:
            if let detail = self.model.detail {
                TujiScreenTitle(localized: detail.list.name)
                self.header(detail)
                self.wordRows(detail)
            }
        }
    }

    private func header(_ detail: WordListDetailResponse) -> some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            Text("\(detail.wordIds.count) 個字 · 已學 \(detail.stats.seen) · 待複習 \(detail.stats.due)")
                .font(.tujiBodySm)
                .foregroundStyle(.tujiInk3)
            if !detail.canStudy {
                Button { self.presentPaywall() } label: {
                    Label(
                        detail.list.locked
                            ? "這個詞表超出目前方案的數量，已鎖定。升級或調整排序即可繼續使用。"
                            : "會員才能從詞表學習與新增字。",
                        systemImage: "lock.fill"
                    )
                    .font(.tujiBodySm)
                    .foregroundStyle(.tujiInk2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
            }
            if !self.model.studyModes.isEmpty {
                HStack(spacing: Space.s3) {
                    ForEach(self.model.studyModes, id: \.self) { mode in
                        NavigationLink(value: WordListRoute.study(listId: detail.list.id, mode: mode)) {
                            Text(mode == .new ? "學新字" : "複習")
                                .font(.tujiBodySm(.strong))
                                .foregroundStyle(.tujiInk)
                                .frame(maxWidth: .infinity)
                                .frame(height: 48)
                                .background(mode == .new ? Color.tujiBrandPrimary : .tujiPaper2)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(.horizontal, Space.s4)
        .padding(.bottom, Space.s3)
    }

    @ViewBuilder
    private func wordRows(_ detail: WordListDetailResponse) -> some View {
        if detail.wordIds.isEmpty {
            TujiBlankState(
                icon: "text.badge.plus",
                kind: .empty("還沒有字。在單字頁按「加入詞表」就能放進來。")
            )
        } else {
            TujiSection {
                ForEach(detail.wordIds, id: \.self) { id in
                    self.wordRow(id)
                }
            }
        }
    }

    @ViewBuilder
    private func wordRow(_ id: String) -> some View {
        let word = self.words.find(id: id)
        let row = TujiRow(
            leading: {
                HStack(spacing: Space.s3) {
                    LazyImage(url: word?.imageURL) { state in
                        if let image = state.image {
                            image.resizable().aspectRatio(contentMode: .fill)
                        } else {
                            Color.tujiPaper2
                        }
                    }
                    .frame(width: 44, height: 44)
                    .clipped()
                    TujiRowLabel(
                        localized: word?.word ?? id,
                        localizedSubtitle: self.settings.current.showZh ? word?.chinese : nil
                    )
                }
            },
            trailing: {
                if self.editing {
                    TujiNavIcon(systemName: "minus.circle", label: "從詞表移除") {
                        Task { await self.remove(id) }
                    }
                } else {
                    TujiRowAccessory(value: nil, showsArrow: true)
                }
            }
        )
        if self.editing {
            row
        } else {
            NavigationLink(value: NavRoute.wordDetail(id: id)) { row }
                .tujiRowStyle()
        }
    }

    // MARK: - Actions

    private func remove(_ id: String) async {
        let outcome = await self.model.remove(id)
        if case let .failed(message) = outcome { self.failure = message }
        await self.store.reload()
    }

    private func rename(_ name: String) async -> WordListNameResult {
        guard let list = self.model.detail?.list else { return .done }
        switch await self.store.rename(list, to: name) {
        case .done, .missing:
            await self.model.load()
            return .done
        case .needsUpgrade:
            return .needsUpgrade
        case .atLimit:
            return .message(tujiLocalized("已達上限"))
        case let .failed(message):
            return .message(message)
        }
    }

    private func delete() async {
        guard let list = self.model.detail?.list else { return }
        switch await self.store.delete(list) {
        case .done, .missing: self.dismiss()
        case .needsUpgrade, .atLimit: break
        case let .failed(message): self.failure = message
        }
    }
}
