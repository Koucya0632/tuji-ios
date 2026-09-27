// Lets the user change which 圖鑑 (categories) feed the study queue and the
// 主題進度 totals after onboarding. Mirrors the web settings picker
// (app/settings/SettingsClient.tsx): a multi-select grid plus 全選 / 清除.
//
// Writes straight into SettingsStore via update(_:) — immediate apply +
// debounced POST /api/users/settings, no save button. Each change also
// invalidates StudyStatsStore so Today's due / new counts refetch against
// the new category scope; the progress totals recompute client-side from
// the same selection (ProgressStore.seenCount / totalCount), so they need
// no invalidation.

import SwiftUI

struct StudyCategoriesPickerView: View {
    @Environment(SettingsStore.self) private var store
    @Environment(CategoriesStore.self) private var categories
    /// Read for the server's `studyableCategories`; observing it re-renders
    /// the locks when the entitlement snapshot arrives.
    @State private var atlas = AtlasStore.shared
    @State private var showPaywall = false

    /// nil = every theme may be studied (members, and before the cutover).
    private var studyable: Set<String>? {
        self.atlas.entitlement?.membership?.studyableCategories.map(Set.init)
    }

    private func isLocked(_ id: String) -> Bool {
        guard let studyable else { return false }
        return !studyable.contains(id)
    }

    var body: some View {
        VStack(spacing: 0) {
            TujiNavBar(leading: .back)
            self.list
        }
        .background(.tujiPaper)
        .navigationTitle("學習主題")
        .toolbar(.hidden, for: .navigationBar)
        .task { await self.categories.loadIfNeeded() }
        // Reachable from 今日 as well as 設定, so it cannot count on 設定 having
        // asked. A launch whose read failed asks nowhere else.
        .task { await self.store.loadIfNeeded() }
        .sheet(isPresented: self.$showPaywall) { PaywallView() }
    }

    private var list: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.s4) {
                Text("選你想學的主題。學新字與主題進度只會算這些主題；複習不分主題，所有學過的字都會排進來。")
                    .font(.tujiLabel)
                    .foregroundStyle(.tujiInk3)
                if self.studyable != nil {
                    Text("上鎖的主題成為會員後即可學習。")
                        .font(.tujiLabel)
                        .foregroundStyle(.tujiInk3)
                }

                if !self.store.isEditable {
                    // The grid computes each new selection from the one on
                    // screen, so a grid drawn from the defaults would turn
                    // 「add one」 into 「replace them all」.
                    SettingsLoadStatus()
                } else if self.categories.categories.isEmpty {
                    HStack {
                        TujiPageLoading()
                        Text("載入主題中…")
                            .font(.tujiLabel)
                            .foregroundStyle(.tujiInk3)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, Space.s4)
                } else {
                    self.actions
                    self.grid
                }
            }
            .padding(.horizontal, Space.s4)
            .padding(.top, Space.s3)
            .padding(.bottom, Space.s6)
        }
        .background(.tujiPaper)
        .task { await self.categories.loadIfNeeded() }
    }

    private var selectedIds: Set<String> {
        Set(self.store.current.studyCategories)
    }

    private var actions: some View {
        HStack(spacing: Space.s3) {
            // Only what may be studied: selecting a locked theme would count
            // toward nothing.
            Button("全選") {
                self.setSelection(self.categories.categories.map(\.id).filter { !self.isLocked($0) })
            }
            Button("清除") { self.setSelection([]) }
            Spacer()
            Text("已選 \(self.selectedIds.count) 個")
                .font(.tujiLabel)
                .foregroundStyle(.tujiInk3)
        }
        .font(.tujiBodySm(.strong))
        .tint(.tujiBrandSecondary)
    }

    private var grid: some View {
        LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: Space.s2), count: 3),
            spacing: Space.s2
        ) {
            ForEach(self.categories.categories) { c in
                let locked = self.isLocked(c.id)
                self.tile(category: c, selected: !locked && self.selectedIds.contains(c.id), locked: locked) {
                    if locked {
                        self.showPaywall = true
                    } else {
                        self.toggle(c.id)
                    }
                }
            }
        }
    }

    private func tile(
        category: TujiCategory,
        selected: Bool,
        locked: Bool,
        action: @escaping () -> Void
    )
        -> some View
    {
        Button(action: action) {
            HStack(spacing: Space.s1) {
                if locked {
                    Image(systemName: "lock.fill")
                        .font(.tujiIcon(10, weight: .semibold))
                        .foregroundStyle(.tujiInk3)
                }
                Text(category.nameZh)
                    .font(.tujiLabel)
                    .foregroundStyle(locked ? .tujiInk3 : .tujiInk2)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .padding(.vertical, Space.s4)
            .frame(maxWidth: .infinity)
            .background(
                selected ? Color.tujiCurrent.opacity(0.18) : .tujiPaper,
                in: .rect(cornerRadius: Radius.r0)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Radius.r0)
                    .stroke(
                        selected ? Color.tujiCurrent : .tujiRule,
                        lineWidth: selected ? 1.5 : 1
                    )
            )
        }
        .buttonStyle(.plain)
        .accessibilityHint(locked ? Text("成為會員後可學習") : Text(verbatim: ""))
    }

    private func toggle(_ id: String) {
        var next = self.selectedIds
        if next.contains(id) {
            next.remove(id)
        } else {
            next.insert(id)
        }
        self.setSelection(Array(next))
    }

    /// Persist the new selection. The new-card flow + progress totals read
    /// studyCategories directly (client-side), so no cache needs busting:
    /// stats are global and the new-words count derives from ProgressStore.
    private func setSelection(_ ids: [String]) {
        self.store.update { $0.studyCategories = ids.sorted() }
    }
}

#Preview {
    NavigationStack {
        StudyCategoriesPickerView()
            .environment(SettingsStore.shared)
            .environment(CategoriesStore.shared)
    }
}
