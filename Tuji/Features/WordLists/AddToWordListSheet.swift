// 加入詞表 — one word, every list, a checkbox each. Changes apply as they are
// ticked, like the rest of this app's switches.

import SwiftUI

struct AddToWordListSheet: View {
    let wordId: String

    @Environment(WordListsStore.self) private var store
    @Environment(\.presentPaywall) private var presentPaywall
    @State private var lists: [WordList] = []
    @State private var phase: LoadPhase = .idle
    @State private var message: String?
    @State private var showCreate = false
    @State private var busy: Set<String> = []

    var body: some View {
        TujiSheetShell(title: "加入詞表", height: 420) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    self.content
                    if let message {
                        Text(verbatim: message)
                            .font(.tujiBodySm)
                            .foregroundStyle(.tujiAlert)
                            .padding(.horizontal, Space.s4)
                            .padding(.top, Space.s2)
                    }
                }
                .padding(.bottom, Space.s5)
            }
        }
        .task { await self.load() }
        .sheet(isPresented: self.$showCreate) {
            WordListNameSheet(title: "建立詞表", actionTitle: "建立並加入") { name in
                await self.createAndAdd(name)
            }
            .paywallHost()
        }
    }

    @ViewBuilder
    private var content: some View {
        switch self.phase {
        case .idle, .loading:
            TujiPageLoading()
                .frame(maxWidth: .infinity)
                .padding(.top, Space.s5)
        case .failed:
            TujiBlankState(kind: .failed, retry: { await self.load() })
        case .loaded:
            TujiSection {
                ForEach(self.lists) { list in
                    TujiRow(
                        leading: {
                            TujiRowLabel(
                                localized: list.name,
                                localizedSubtitle: list.locked
                                    ? tujiLocalized("已鎖定")
                                    : tujiLocalized("\(list.wordCount) 個字")
                            )
                        },
                        trailing: {
                            TujiCheckbox(isOn: Binding(
                                get: { list.containsWord ?? false },
                                set: { on in Task { await self.set(list, present: on) } }
                            ))
                            .disabled(list.locked || self.busy.contains(list.id))
                        }
                    )
                }
                if self.store.canCreate {
                    Button { self.showCreate = true } label: {
                        TujiRow("建立新詞表", showsArrow: false)
                    }
                    .tujiRowStyle()
                }
            }
        }
    }

    private func load() async {
        self.phase = self.phase == .loaded ? .loaded : .loading
        do {
            self.lists = try await self.store.lists(containing: self.wordId)
            self.phase = .loaded
            // Nothing to tick yet: go straight to naming the first one.
            if self.lists.isEmpty, self.store.canCreate { self.showCreate = true }
        } catch {
            self.phase = self.phase.afterFailure
        }
    }

    private func set(_ list: WordList, present: Bool) async {
        self.busy.insert(list.id)
        defer { self.busy.remove(list.id) }
        self.message = nil
        switch await self.store.setWord(self.wordId, in: list, present: present) {
        case .done:
            // The store rebuilt this row with the new count and tick.
            if let updated = self.store.lists.first(where: { $0.id == list.id }),
               let i = self.lists.firstIndex(where: { $0.id == list.id })
            {
                self.lists[i] = updated
            }
        case .needsUpgrade:
            self.presentPaywall()
        case .atLimit:
            self.message = tujiLocalized("這個詞表的字數已達上限")
        case .missing:
            await self.load()
        case let .failed(text):
            self.message = text
        }
    }

    private func createAndAdd(_ name: String) async -> WordListNameResult {
        let (outcome, created) = await self.store.create(name: name)
        switch outcome {
        case .done:
            if let created { await self.set(created, present: true) }
            await self.load()
            return .done
        case .needsUpgrade:
            return .needsUpgrade
        case .atLimit:
            return .message(tujiLocalized("詞表數量已達上限，刪除一些後再建立"))
        case .missing:
            return .done
        case let .failed(text):
            return .message(text)
        }
    }
}

/// The word page's 加入詞表 control. Hidden under membership v1; a lock for a
/// non-member, which opens the paywall.
struct WordListButton: View {
    let wordId: String
    var size: CGFloat = 40

    @Environment(WordListsStore.self) private var store
    @Environment(\.presentPaywall) private var presentPaywall
    @State private var showSheet = false
    private let access: any MemberAccessReading = LiveMemberAccess()

    private var level: MemberAccessLevel {
        self.access.level(.wordListAdd)
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            // Always drawn, so the `.task` below runs — see `TaskAnchor`.
            TaskAnchor()
            if self.level != .hidden {
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    if self.level == .locked {
                        self.presentPaywall()
                    } else {
                        self.showSheet = true
                    }
                } label: {
                    ZStack(alignment: .bottomTrailing) {
                        Rectangle().fill(Color.tujiPaper2)
                        Image(systemName: "text.badge.plus")
                            .font(.tujiIcon(self.size * 0.38, weight: .semibold))
                            .foregroundStyle(.tujiInk2)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                        if self.level == .locked {
                            Image(systemName: "lock.fill")
                                .font(.tujiIcon(9, weight: .bold))
                                .foregroundStyle(.tujiInk3)
                                .padding(4)
                        }
                    }
                    .frame(width: self.size, height: self.size)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("加入詞表"))
            }
        }
        .task {
            guard self.level != .hidden else { return }
            await self.store.loadIfNeeded()
        }
        .sheet(isPresented: self.$showSheet) {
            // Hosted here, so the sheet's own lock opens 付費頁 on top of it.
            AddToWordListSheet(wordId: self.wordId).paywallHost()
        }
    }
}
