// Progress tab — full §III.L surface. Pulls /api/users/progress (streak
// + 42-cell heatmap) and overlays it on the locally-known WordsStore
// totals + LocalCache learned count.
//
// "清除進度" calls DELETE /api/users/progress (wipes mastery + study
// logs; preserves favorites + settings).

import Observation
import OSLog
import SwiftUI

@MainActor
@Observable
final class ProgressVM {
    var clearing: Bool = false
    var clearError: Error?

    private let log = Logger(subsystem: "app.tuji.ios", category: "progress")

    /// Streak + heatmap reads now live on ProgressStore.shared so Today /
    /// Me / CompleteView share the same fetched copy. This VM just owns
    /// the "clear progress" action.
    ///
    /// Server-side `clearLearningProgress` wipes user_cards too, so the
    /// stats store has to be invalidated alongside progress — otherwise
    /// the Study tab shows the pre-wipe due/seen counts for up to 30s.
    func clearProgress(cache: LocalCache, progress: ProgressStore, studyStats: StudyStatsStore) async {
        self.clearing = true
        self.clearError = nil
        defer { self.clearing = false }
        do {
            try await APIClient.shared.delete(.usersProgress)
            // Reset the local learned cache too — the completion % and
            // category breakdown read it, and sync is union-only so a
            // stale local set would resurrect the cleared ids at next
            // sign-in.
            cache.clearLearned()
            progress.invalidate()
            studyStats.invalidate()
            async let p: Void = progress.reload()
            async let s: Void = studyStats.reload()
            await p
            await s
        } catch {
            self.clearError = error
            self.log.error("clear failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}

struct ProgressTabView: View {
    @Environment(LocalCache.self) private var cache
    @Environment(AuthService.self) private var auth
    @Environment(WordsStore.self) private var words
    @Environment(CategoriesStore.self) private var categories
    @Environment(ProgressStore.self) private var progress
    @Environment(StudyStatsStore.self) private var studyStats

    @State private var vm = ProgressVM()
    @State private var showClearConfirm = false

    private var isGuest: Bool {
        if case .signedIn = auth.state { return false }
        return true
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.s5) {
                Text("進度")
                    .font(.tujiH2)
                    .foregroundStyle(.tujiInk)

                self.sectionHeader("總覽")
                self.completionCard
                self.streakRow
                self.heatmapCard

                self.sectionHeader("明細")
                self.categoryBreakdownCard

                if !self.isGuest {
                    self.clearButton
                }
            }
            .padding(.horizontal, Space.s6)
            .padding(.top, Space.s4)
            .padding(.bottom, Space.s24)
        }
        .background(.tujiBg)
        .refreshable {
            if !self.isGuest {
                self.progress.invalidate()
                await self.progress.reload()
            }
            await self.words.loadIfNeeded()
        }
        .task {
            await self.words.loadIfNeeded()
            await self.categories.loadIfNeeded()
            if !self.isGuest { await self.progress.loadIfStale() }
        }
        .alert("清除學習進度", isPresented: self.$showClearConfirm) {
            Button("取消", role: .cancel) {}
            Button("確定清除", role: .destructive) {
                Task {
                    await self.vm.clearProgress(
                        cache: self.cache,
                        progress: self.progress,
                        studyStats: self.studyStats
                    )
                }
            }
        } message: {
            Text("掌握度、SRS 排程、學習紀錄會被清空。\n收藏與設定不受影響。")
        }
    }

    // MARK: - Completion card

    /// Words studied at least once (server "seen"), summed across categories.
    private var seenTotal: Int {
        self.progress.categoryProgress.reduce(0) { $0 + $1.seen }
    }

    /// Total published words. Server count when available, else the locally
    /// known dictionary size (guests / before progress loads).
    private var dictTotal: Int {
        let serverTotal = self.progress.categoryProgress.reduce(0) { $0 + $1.total }
        return serverTotal > 0 ? serverTotal : self.words.words.count
    }

    private var completionCard: some View {
        let learned = self.seenTotal
        let total = self.dictTotal
        let ratio = total > 0 ? Double(learned) / Double(total) : 0
        let pct = Int((ratio * 100).rounded())
        return VStack(alignment: .leading, spacing: Space.s3) {
            Text("圖鑑完成度")
                .font(.tujiOverline)
                .tracking(2)
                .foregroundStyle(.tujiInk3)
            HStack(alignment: .firstTextBaseline) {
                Text("\(pct)%")
                    .font(.system(size: 44, weight: .heavy))
                    .foregroundStyle(.tujiInk)
                    .contentTransition(.numericText())
                Spacer()
            }
            self.progressBar(ratio: ratio)
            Text("已學 \(learned) / 共 \(total) 字")
                .font(.tujiCaption)
                .foregroundStyle(.tujiInk3)
        }
        .padding(Space.s5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.tujiCard, in: .rect(cornerRadius: Radius.lg))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg)
                .stroke(.tujiInk4.opacity(0.2), lineWidth: 1)
        )
    }

    private func progressBar(ratio: Double) -> some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(.tujiInk4.opacity(0.15))
                RoundedRectangle(cornerRadius: 4)
                    .fill(.tujiTeal)
                    .frame(width: geo.size.width * min(1.0, max(0, ratio)))
                    .animation(.spring(duration: 0.5), value: ratio)
            }
        }
        .frame(height: 8)
    }

    // MARK: - Streak row (2 stat cards)

    private var streakRow: some View {
        HStack(spacing: Space.s3) {
            self.statTile(
                label: "目前連勝",
                value: self.progress.streak?.current ?? 0,
                unit: "天",
                icon: "flame.fill",
                tint: .tujiCoral
            )
            self.statTile(
                label: "最長連勝",
                value: self.progress.streak?.longest ?? 0,
                unit: "天",
                icon: "trophy.fill",
                tint: .tujiInk
            )
        }
    }

    private func statTile(label: String, value: Int, unit: String, icon: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: icon).foregroundStyle(tint)
                Text(label)
                    .font(.tujiOverline)
                    .tracking(2)
                    .foregroundStyle(.tujiInk3)
            }
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("\(value)")
                    .font(.system(size: 32, weight: .heavy))
                    .foregroundStyle(.tujiInk)
                    .contentTransition(.numericText())
                Text(unit)
                    .font(.system(size: 13, weight: .heavy))
                    .foregroundStyle(.tujiInk3)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Space.s4)
        .background(.tujiCard, in: .rect(cornerRadius: Radius.lg))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg)
                .stroke(.tujiInk4.opacity(0.2), lineWidth: 1)
        )
    }

    // MARK: - Heatmap

    private var heatmapCard: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            HStack {
                Text("最近 6 週")
                    .font(.tujiOverline)
                    .tracking(2)
                    .foregroundStyle(.tujiTeal)
                Spacer()
                Text("\(self.activeDayCount) 個活躍日")
                    .font(.tujiCaption)
                    .foregroundStyle(.tujiInk3)
            }
            if self.progress.heatmap.isEmpty {
                self.heatmapEmpty
            } else {
                HeatmapGrid(cells: self.progress.heatmap)
            }
        }
        .padding(Space.s5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.tujiCard, in: .rect(cornerRadius: Radius.lg))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg)
                .stroke(.tujiInk4.opacity(0.2), lineWidth: 1)
        )
    }

    private var activeDayCount: Int {
        // swiftlint:disable:next empty_count
        self.progress.heatmap.count { $0.count > 0 }
    }

    private var heatmapEmpty: some View {
        VStack(spacing: Space.s2) {
            Mascot(pose: .sleep, size: 56)
            Text(self.isGuest ? "登入後才能看活躍熱力圖" : "還沒有學習紀錄")
                .font(.tujiCaption)
                .foregroundStyle(.tujiInk3)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Space.s5)
    }

    // MARK: - Section header

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.tujiOverline)
            .tracking(2)
            .foregroundStyle(.tujiInk3)
            .padding(.top, Space.s2)
    }

    // MARK: - Category breakdown (明細)

    private struct CategoryStat: Identifiable {
        let id: String
        let emoji: String
        let nameZh: String
        let learned: Int
        let total: Int
        var ratio: Double { self.total > 0 ? Double(self.learned) / Double(self.total) : 0 }
    }

    /// Per-category seen/total from the server, named + ordered via
    /// CategoriesStore. Categories with no published cards are dropped.
    /// Falls back to raw progress rows if the category list hasn't loaded.
    private var categoryStats: [CategoryStat] {
        let prog = self.progress.categoryProgress.filter { $0.total > 0 }
        guard !prog.isEmpty else { return [] }
        let byId = Dictionary(prog.map { ($0.category, $0) }, uniquingKeysWith: { a, _ in a })
        if !self.categories.categories.isEmpty {
            return self.categories.categories.compactMap { c in
                guard let p = byId[c.id] else { return nil }
                return CategoryStat(
                    id: c.id,
                    emoji: c.emoji,
                    nameZh: c.nameZh,
                    learned: p.seen,
                    total: p.total
                )
            }
        }
        return prog.map { p in
            CategoryStat(
                id: p.category,
                emoji: "📚",
                nameZh: p.category,
                learned: p.seen,
                total: p.total
            )
        }
    }

    private var emptyBreakdownMessage: String {
        if self.isGuest { return "登入後顯示分類進度" }
        return "還沒有學習紀錄"
    }

    private var categoryBreakdownCard: some View {
        VStack(alignment: .leading, spacing: Space.s4) {
            if self.categoryStats.isEmpty {
                Text(self.emptyBreakdownMessage)
                    .font(.tujiCaption)
                    .foregroundStyle(.tujiInk3)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, Space.s4)
            } else {
                ForEach(self.categoryStats) { stat in
                    self.categoryRow(stat)
                }
            }
        }
        .padding(Space.s5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.tujiCard, in: .rect(cornerRadius: Radius.lg))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg)
                .stroke(.tujiInk4.opacity(0.2), lineWidth: 1)
        )
    }

    private func categoryRow(_ stat: CategoryStat) -> some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack(spacing: Space.s2) {
                Text(stat.emoji).font(.system(size: 18))
                Text(stat.nameZh)
                    .font(.system(size: 14, weight: .heavy))
                    .foregroundStyle(.tujiInk)
                Spacer()
                Text("\(stat.learned) / \(stat.total)")
                    .font(.tujiCaption)
                    .foregroundStyle(.tujiInk3)
                    .contentTransition(.numericText())
            }
            self.progressBar(ratio: stat.ratio)
        }
    }

    private var clearButton: some View {
        Button(role: .destructive) {
            self.showClearConfirm = true
        } label: {
            HStack(spacing: Space.s2) {
                if self.vm.clearing {
                    ProgressView().tint(.tujiCoral)
                } else {
                    Image(systemName: "trash")
                }
                Text(self.vm.clearing ? "清除中…" : "清除進度")
            }
            .font(.system(size: 14, weight: .heavy))
            .foregroundStyle(.tujiCoral)
            .frame(maxWidth: .infinity)
            .padding(.vertical, Space.s3)
            .background(.tujiCoral.opacity(0.08), in: .rect(cornerRadius: Radius.lg))
        }
        .buttonStyle(.plain)
        .disabled(self.vm.clearing)
    }
}

// MARK: - Heatmap grid

struct HeatmapGrid: View {
    let cells: [HeatmapCell]
    /// 7 columns laid out top → bottom, then left → right by week.
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 5), count: 7)

    var body: some View {
        VStack(spacing: 8) {
            self.weekdayHeader
            LazyVGrid(columns: self.columns, spacing: 5) {
                ForEach(Array(self.cells.enumerated()), id: \.offset) { _, cell in
                    RoundedRectangle(cornerRadius: 4)
                        .fill(self.color(for: cell))
                        .overlay(
                            RoundedRectangle(cornerRadius: 4)
                                .stroke(cell.future ? .tujiInk4.opacity(0.15) : .clear, lineWidth: 1)
                        )
                        .aspectRatio(1, contentMode: .fit)
                }
            }
            self.legend
        }
    }

    private var weekdayHeader: some View {
        let labels = ["日", "一", "二", "三", "四", "五", "六"]
        return HStack(spacing: 5) {
            ForEach(labels, id: \.self) { l in
                Text(l)
                    .font(.system(size: 10, weight: .heavy))
                    .foregroundStyle(.tujiInk4)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private var legend: some View {
        HStack(spacing: 6) {
            Text("少")
                .font(.system(size: 10, weight: .heavy))
                .foregroundStyle(.tujiInk4)
            ForEach(0..<4, id: \.self) { lvl in
                RoundedRectangle(cornerRadius: 3)
                    .fill(self.tintForLevel(lvl))
                    .frame(width: 14, height: 14)
            }
            Text("多")
                .font(.system(size: 10, weight: .heavy))
                .foregroundStyle(.tujiInk4)
            Spacer()
        }
    }

    private func color(for cell: HeatmapCell) -> Color {
        if cell.future { return .tujiCard }
        return self.tintForLevel(self.strength(for: cell.count))
    }

    private func strength(for count: Int) -> Int {
        switch count {
        case 0: 0
        case 1...4: 1
        case 5...12: 2
        default: 3
        }
    }

    private func tintForLevel(_ level: Int) -> Color {
        switch level {
        case 0: Color.tujiInk4.opacity(0.15)
        case 1: .tujiTealSoft
        case 2: Color(red: 0.48, green: 0.69, blue: 0.69)
        default: .tujiTeal
        }
    }
}

#Preview {
    NavigationStack {
        ProgressTabView()
            .environment(LocalCache.shared)
            .environment(AuthService.shared)
            .environment(WordsStore.shared)
            .environment(CategoriesStore.shared)
            .environment(ProgressStore.shared)
            .environment(StudyStatsStore.shared)
    }
}
