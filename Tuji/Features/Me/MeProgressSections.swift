// Progress tab — full §III.L surface. Pulls /api/users/progress (streak
// + 42-cell heatmap) and overlays it on the locally-known WordsStore
// totals + LocalCache learned count.
//
// "清除學習進度" (DELETE /api/users/progress) lives in 設定 → 帳號 — a
// destructive account action didn't belong one tap from the stats screen.

import Observation
import OSLog
import SwiftUI

@MainActor
@Observable
final class ProgressVM {
    var clearing: Bool = false
    var clearError: Error?

    private let repository: ProgressRepository
    private let log = Logger(subsystem: "app.tuji.ios", category: "progress")

    init(repository: ProgressRepository = LiveProgressRepository.shared) {
        self.repository = repository
    }

    /// Streak + heatmap reads now live on ProgressStore.shared so Today /
    /// Me / CompleteView share the same fetched copy. This VM just owns
    /// the "clear progress" action.
    ///
    /// Server-side `clearLearningProgress` wipes user_cards too, so the
    /// stats store has to be invalidated alongside progress — otherwise
    /// the Study tab shows the pre-wipe due/seen counts for up to 30s.
    /// Invoked from 設定 → 帳號 → 清除學習進度.
    func clearProgress(cache: LocalCache, progress: ProgressStore, studyStats: StudyStatsStore) async {
        self.clearing = true
        self.clearError = nil
        defer { self.clearing = false }
        do {
            try await self.repository.clearProgress()
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

/// The 進度 tab's content, now a section stack inside 我 (D.8).
///
/// It stopped being a tab because it was never a *place* — it is a readout
/// about the user, which is what 我 is for. Nothing about the numbers changed;
/// the screen chrome (its own ScrollView, its own 進度 title, its own nav bar)
/// belongs to the host now.
struct MeProgressSections: View {
    @Environment(AuthService.self) private var auth
    @Environment(WordsStore.self) private var words
    @Environment(CategoriesStore.self) private var categories
    @Environment(ProgressStore.self) private var progress
    @Environment(SettingsStore.self) private var settings

    private var isGuest: Bool {
        if case .signedIn = auth.state { return false }
        return true
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s5) {
            self.completionCard
            self.streakRow
                .padding(.horizontal, Space.s4)
            self.heatmapSection
                .padding(.horizontal, Space.s4)
            self.categoryBreakdownCard
                .padding(.horizontal, Space.s4)
        }
        .task {
            await self.words.loadIfNeeded()
            await self.categories.loadIfNeeded()
            await self.settings.loadIfNeeded()
            if !self.isGuest { await self.progress.loadIfStale() }
        }
    }

    // MARK: - Completion card

    /// Words studied at least once (server "seen") in the selected categories.
    private var seenTotal: Int {
        self.progress.seenCount(filter: self.settings.current.studyCategories)
    }

    /// Total published words in the selected categories. Server count when
    /// available, else the locally known dictionary size (guests / before
    /// progress loads).
    private var dictTotal: Int {
        let serverTotal = self.progress.totalCount(filter: self.settings.current.studyCategories)
        return serverTotal > 0 ? serverTotal : self.words.words.count
    }

    private var completionCard: some View {
        let learned = self.seenTotal
        let total = self.dictTotal
        let ratio = total > 0 ? Double(learned) / Double(total) : 0
        let pct = Int((ratio * 100).rounded())
        // Both this stat and its detail line are scoped to the user's
        // selected 學習主題 (empty selection = all categories), same as the
        // 明細 breakdown below. Label it explicitly so it doesn't read as a
        // whole-catalog number next to Me tab's unscoped 已學字 total.
        let scoped = !self.settings.current.studyCategories.isEmpty
        // The one number on this tab that is *the* number, so it gets the ink
        // block — the same weight the Today hero and the completion screen use.
        return VStack(alignment: .leading, spacing: Space.s2) {
            Text(scoped ? LocalizedStringKey("所選主題完成度") : LocalizedStringKey("圖鑑完成度"))
                .font(.tujiLabel)
                .tracking(0.5)
                .foregroundStyle(.tujiPaper.opacity(0.6))
            Text("\(pct)%")
                .font(.tujiDisplay)
                .foregroundStyle(.tujiTealSoft)
                .contentTransition(.numericText())
            Text(
                scoped
                    ? LocalizedStringKey("已學 \(learned) / 所選主題共 \(total) 字")
                    : LocalizedStringKey("已學 \(learned) / 共 \(total) 字")
            )
            .font(.tujiBodySm)
            .foregroundStyle(.tujiPaper.opacity(0.7))
            TujiProgressBar(progress: ratio, track: .tujiPaper.opacity(0.15), fill: .tujiTealSoft)
                .padding(.top, Space.s2)
        }
        .padding(Space.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.tujiInk)
    }

    // MARK: - Streak row (2 stat cards)

    /// Two columns on paper, no tiles and no flame. A streak is a fact about
    /// the account; the box, the border and the icon were three ways of
    /// insisting on it. When it breaks the number is 0 and one line explains —
    /// it does not turn red, animate, or send the cat out.
    private var streakRow: some View {
        HStack(alignment: .top, spacing: Space.s5) {
            self.streakColumn("目前連勝", value: self.progress.streak?.current ?? 0)
            self.streakColumn("最長連勝", value: self.progress.streak?.longest ?? 0)
            Spacer(minLength: 0)
        }
    }

    private func streakColumn(_ label: LocalizedStringKey, value: Int) -> some View {
        VStack(alignment: .leading, spacing: Space.s1) {
            Text(label)
                .font(.tujiLabel)
                .tracking(0.5)
                .foregroundStyle(.tujiInk3)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("\(value)")
                    .font(.tujiDisplay)
                    .foregroundStyle(.tujiInk)
                    .contentTransition(.numericText())
                Text(verbatim: tujiLocalized("天"))
                    .font(.tujiBodySm)
                    .foregroundStyle(.tujiInk3)
            }
            if value == 0 {
                Text("從今天重新開始")
                    .font(.tujiBodySm)
                    .foregroundStyle(.tujiInk3)
            }
        }
    }

    // MARK: - Heatmap

    private var heatmapSection: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            HStack {
                Text("最近 6 週")
                    .font(.tujiLabel)
                    .tracking(0.5)
                    .foregroundStyle(.tujiInk3)
                Spacer()
                Text("\(self.activeDayCount) 個活躍日")
                    .font(.tujiLabel)
                    .tracking(0.5)
                    .foregroundStyle(.tujiInk3)
            }
            if self.progress.heatmap.isEmpty {
                self.heatmapEmpty
            } else {
                HeatmapGrid(cells: self.progress.heatmap)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var activeDayCount: Int {
        // swiftlint:disable:next empty_count
        self.progress.heatmap.count { $0.count > 0 }
    }

    private var heatmapEmpty: some View {
        MascotEmptyState(
            pose: .sleep,
            title: self.isGuest ? "登入後才能看活躍熱力圖" : "還沒有學習紀錄",
            compact: true
        )
    }

    // MARK: - Category breakdown (明細)

    private struct CategoryStat: Identifiable {
        let id: String
        let nameZh: String
        let learned: Int
        let total: Int
        var ratio: Double {
            self.total > 0 ? Double(self.learned) / Double(self.total) : 0
        }
    }

    /// Per-category seen/total from the server, named + ordered via
    /// CategoriesStore. Categories with no published cards are dropped.
    /// Scoped to the user's selected study categories (empty = all) so the
    /// breakdown matches the completion card above. Falls back to raw
    /// progress rows if the category list hasn't loaded.
    private var categoryStats: [CategoryStat] {
        let selected = self.settings.current.studyCategories
        let scoped = selected.isEmpty
            ? self.progress.categoryProgress
            : self.progress.categoryProgress.filter { selected.contains($0.category) }
        let prog = scoped.filter { $0.total > 0 }
        guard !prog.isEmpty else { return [] }
        let byId = Dictionary(prog.map { ($0.category, $0) }, uniquingKeysWith: { a, _ in a })
        if !self.categories.categories.isEmpty {
            return self.categories.categories.compactMap { c in
                guard let p = byId[c.id] else { return nil }
                return CategoryStat(
                    id: c.id,
                    nameZh: c.nameZh,
                    learned: p.seen,
                    total: p.total
                )
            }
        }
        return prog.map { p in
            CategoryStat(
                id: p.category,
                nameZh: p.category,
                learned: p.seen,
                total: p.total
            )
        }
    }

    private var emptyBreakdownMessage: LocalizedStringKey {
        if self.isGuest { return "登入後顯示分類進度" }
        return "還沒有學習紀錄"
    }

    private var categoryBreakdownCard: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            if self.categoryStats.isEmpty {
                Text(self.emptyBreakdownMessage)
                    .font(.tujiLabel)
                    .foregroundStyle(.tujiInk3)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, Space.s3)
            } else {
                ForEach(self.categoryStats) { stat in
                    self.categoryRow(stat)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func categoryRow(_ stat: CategoryStat) -> some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack(spacing: Space.s2) {
                Text(stat.nameZh)
                    .font(.tujiH3)
                    .foregroundStyle(.tujiInk)
                Spacer()
                Text("\(stat.learned) / \(stat.total)")
                    .font(.tujiMono)
                    .foregroundStyle(.tujiInk3)
                    .contentTransition(.numericText())
            }
            TujiProgressBar(progress: stat.ratio, track: .tujiPaper3, fill: .tujiTeal)
        }
        .frame(minHeight: 72)
    }
}

// MARK: - Heatmap grid

struct HeatmapGrid: View {
    let cells: [HeatmapCell]
    @Environment(SettingsStore.self) private var settings
    /// 7 columns laid out top → bottom, then left → right by week.
    private let columns = Array(repeating: GridItem(.flexible(), spacing: Space.s1), count: 7)

    var body: some View {
        VStack(spacing: 8) {
            self.weekdayHeader
            LazyVGrid(columns: self.columns, spacing: Space.s1) {
                ForEach(Array(self.cells.enumerated()), id: \.offset) { _, cell in
                    // Square, like everything else. A rounded heat cell is the
                    // GitHub contribution graph's own signature, and this grid
                    // was carrying it verbatim.
                    Rectangle()
                        .fill(self.color(for: cell))
                        .aspectRatio(1, contentMode: .fit)
                }
            }
            self.legend
        }
    }

    private var weekdayHeader: some View {
        // Sunday-first, matching the heatmap's column order. Index-keyed:
        // English's very-short symbols repeat ("S", "T").
        let f = DateFormatter()
        f.locale = self.settings.current.uiLanguage.locale
        let labels = f.veryShortStandaloneWeekdaySymbols ?? ["日", "一", "二", "三", "四", "五", "六"]
        return HStack(spacing: 5) {
            ForEach(labels.indices, id: \.self) { i in
                Text(labels[i])
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.tujiInk3)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private var legend: some View {
        HStack(spacing: 6) {
            Text("少")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.tujiInk3)
            ForEach(0..<4, id: \.self) { lvl in
                RoundedRectangle(cornerRadius: 3)
                    .fill(self.tintForLevel(lvl))
                    .frame(width: 14, height: 14)
            }
            Text("多")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.tujiInk3)
            Spacer()
        }
    }

    private func color(for cell: HeatmapCell) -> Color {
        if cell.future { return .tujiPaper }
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
        case 0: Color.tujiPaper3
        case 1: .tujiTealSoft
        case 2: Color.tujiTeal
        default: .tujiTeal
        }
    }
}

#Preview {
    NavigationStack {
        ScrollView { MeProgressSections() }
            .environment(LocalCache.shared)
            .environment(AuthService.shared)
            .environment(WordsStore.shared)
            .environment(CategoriesStore.shared)
            .environment(ProgressStore.shared)
            .environment(StudyStatsStore.shared)
            .environment(SettingsStore.shared)
    }
}
