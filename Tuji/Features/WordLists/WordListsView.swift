// 詞表 — the account's 個人詞表 in the current learning language.
//
// Order matters beyond taste: after a downgrade the first lists in this order
// stay usable, so 排序 is how a person chooses which ones. It is never gated.

import SwiftUI

struct WordListsView: View {
    @Environment(WordListsStore.self) private var store
    @State private var showCreate = false
    @State private var showPaywall = false
    @State private var reordering = false
    @State private var limitMessage: String?
    @State private var failure: String?

    var body: some View {
        VStack(spacing: 0) {
            TujiNavBar(leading: .back) {
                if self.store.lists.count > 1 {
                    TujiNavTextAction(title: self.reordering ? "完成" : "排序") {
                        self.reordering.toggle()
                    }
                }
                if self.store.canCreate {
                    TujiNavIcon(systemName: "plus", label: "建立詞表") { self.showCreate = true }
                }
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    TujiScreenTitle("詞表")
                    self.summary
                    self.content
                }
                .padding(.bottom, Space.s6)
            }
        }
        .background(.tujiPaper)
        .navigationTitle("詞表")
        .toolbar(.hidden, for: .navigationBar)
        .task { await self.store.loadIfNeeded() }
        .refreshable { await self.store.reload() }
        .sheet(isPresented: self.$showCreate) {
            WordListNameSheet(title: "建立詞表", actionTitle: "建立") { name in
                await self.create(name)
            }
        }
        .sheet(isPresented: self.$showPaywall) { PaywallView() }
        .tujiPrompt(
            isPresented: Binding(get: { self.failure != nil }, set: { if !$0 { self.failure = nil } }),
            style: .error,
            title: "無法完成",
            message: "\(self.failure ?? "")",
            primary: TujiPromptAction("知道了") {}
        )
    }

    @ViewBuilder
    private var summary: some View {
        if let limits = self.store.limits, self.store.tier != "free" {
            Text("已建立 \(self.store.lists.count) / \(limits.lists) 張，每張最多 \(limits.words) 個字")
                .font(.tujiBodySm)
                .foregroundStyle(.tujiInk3)
                .padding(.horizontal, Space.s4)
                .padding(.bottom, Space.s3)
        } else if self.store.tier == "free" {
            // A refund leaves the lists in place, read-only.
            Button { self.showPaywall = true } label: {
                Text("會員才能新增或學習詞表。你的詞表仍會保留。")
                    .font(.tujiBodySm)
                    .foregroundStyle(.tujiInk2)
                    .underline()
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, Space.s4)
            .padding(.bottom, Space.s3)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch self.store.phase {
        case .idle, .loading:
            TujiPageLoading()
                .frame(maxWidth: .infinity)
                .padding(.top, Space.s6)
        case .failed:
            TujiBlankState(kind: .failed, retry: { await self.store.reload() })
        case .loaded:
            if self.store.lists.isEmpty {
                VStack(spacing: Space.s4) {
                    TujiBlankState(icon: "list.bullet.rectangle", kind: .empty("還沒有詞表。建立一張，把想一起背的字放進去。"))
                    if self.store.canCreate {
                        BBtn(title: "建立詞表") { self.showCreate = true }
                    }
                }
                .frame(maxWidth: .infinity)
            } else {
                TujiSection {
                    ForEach(Array(self.store.lists.enumerated()), id: \.element.id) { index, list in
                        self.row(list, index: index)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func row(_ list: WordList, index: Int) -> some View {
        if self.reordering {
            TujiRow(
                leading: { self.label(list) },
                trailing: {
                    HStack(spacing: 0) {
                        TujiNavIcon(systemName: "arrow.up", label: "上移") {
                            Task { await self.move(index, by: -1) }
                        }
                        .disabled(index == 0)
                        TujiNavIcon(systemName: "arrow.down", label: "下移") {
                            Task { await self.move(index, by: 1) }
                        }
                        .disabled(index == self.store.lists.count - 1)
                    }
                }
            )
        } else {
            NavigationLink(value: WordListRoute.list(id: list.id)) {
                TujiRow(
                    leading: { self.label(list) },
                    trailing: {
                        if list.locked {
                            Image(systemName: "lock.fill")
                                .font(.tujiIcon(14, weight: .semibold))
                                .foregroundStyle(.tujiInk3)
                                .accessibilityLabel(Text("已鎖定"))
                        }
                        TujiRowAccessory(value: nil, showsArrow: true)
                    }
                )
            }
            .tujiRowStyle()
        }
    }

    private func label(_ list: WordList) -> TujiRowLabel {
        TujiRowLabel(
            localized: list.name,
            localizedSubtitle: tujiLocalized("\(list.wordCount) 個字")
        )
    }

    private func move(_ index: Int, by offset: Int) async {
        guard self.store.lists.indices.contains(index) else { return }
        await self.handle(self.store.move(self.store.lists[index].id, by: offset))
    }

    private func create(_ name: String) async -> String? {
        let (outcome, _) = await self.store.create(name: name)
        switch outcome {
        case .done:
            return nil
        case .needsUpgrade:
            self.showCreate = false
            self.showPaywall = true
            return nil
        case .atLimit:
            return tujiLocalized("詞表數量已達上限，刪除一些後再建立")
        case .missing:
            return nil
        case let .failed(message):
            return message
        }
    }

    private func handle(_ outcome: WordListWriteOutcome) {
        switch outcome {
        case .done, .missing: break
        case .needsUpgrade: self.showPaywall = true
        case .atLimit: self.failure = tujiLocalized("已達上限")
        case let .failed(message): self.failure = message
        }
    }
}
