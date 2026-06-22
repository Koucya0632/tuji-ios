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

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.s5) {
                Text("選你想學的主題。學新字與主題進度只會算這些主題；複習不分主題，所有學過的字都會排進來。")
                    .font(.tujiCaption)
                    .foregroundStyle(.tujiInk3)

                if self.categories.categories.isEmpty {
                    HStack {
                        ProgressView().tint(.tujiTeal)
                        Text("載入主題中…")
                            .font(.tujiCaption)
                            .foregroundStyle(.tujiInk3)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, Space.s5)
                } else {
                    self.actions
                    self.grid
                }
            }
            .padding(.horizontal, Space.s6)
            .padding(.top, Space.s4)
            .padding(.bottom, Space.s24)
        }
        .background(.tujiBg)
        .navigationTitle("學習主題")
        .navigationBarTitleDisplayMode(.inline)
        .task { await self.categories.loadIfNeeded() }
    }

    private var selectedIds: Set<String> {
        Set(self.store.current.studyCategories)
    }

    private var actions: some View {
        HStack(spacing: Space.s4) {
            Button("全選") { self.setSelection(self.categories.categories.map(\.id)) }
            Button("清除") { self.setSelection([]) }
            Spacer()
            Text("已選 \(self.selectedIds.count) 個")
                .font(.tujiCaption)
                .foregroundStyle(.tujiInk3)
        }
        .font(.system(size: 14, weight: .heavy))
        .tint(.tujiTeal)
    }

    private var grid: some View {
        LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: Space.s2), count: 3),
            spacing: Space.s2
        ) {
            ForEach(self.categories.categories) { c in
                self.tile(category: c, selected: self.selectedIds.contains(c.id)) {
                    self.toggle(c.id)
                }
            }
        }
    }

    private func tile(
        category: TujiCategory,
        selected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Text(category.emoji)
                    .font(.system(size: 22))
                Text(category.nameZh)
                    .font(.system(size: 13, weight: .heavy))
                    .foregroundStyle(selected ? .tujiTeal : .tujiInk2)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .padding(.vertical, Space.s3)
            .frame(maxWidth: .infinity)
            .background(
                selected ? Color.tujiTealSoft : .tujiCard,
                in: .rect(cornerRadius: Radius.md)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Radius.md)
                    .stroke(
                        selected ? Color.tujiTeal : .tujiInk4.opacity(0.25),
                        lineWidth: selected ? 1.5 : 1
                    )
            )
        }
        .buttonStyle(.plain)
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
