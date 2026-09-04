// Progress tab — full §III.L surface. Pulls /api/users/progress (streak
// + 42-cell heatmap) and overlays it on the locally-known WordsStore
// totals + LocalCache learned count.
//
// "清除學習進度" (DELETE /api/users/progress) lives in 設定 → 帳號 — a
// destructive account action didn't belong one tap from the stats screen.

import Observation
import OSLog
import SwiftUI

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
    @Environment(LocalCache.self) private var cache
    @Environment(MasteryStore.self) private var mastery

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s5) {
            self.completionCard
            // Directly under 完成度 on purpose. That card answers how *wide*
            // the account has gone and this one how *deep*; they were only ever
            // half an answer apart, and the whole reason this section exists is
            // that the deep half was missing from the screen.
            self.masterySection
                .padding(.horizontal, Space.s4)
            self.streakRow
                .padding(.horizontal, Space.s4)
            self.heatmapSection
                .padding(.horizontal, Space.s4)
            self.categoryBreakdownCard
                .padding(.horizontal, Space.s4)
        }
        .warmsAccumulation(.progressSections, isGuest: self.auth.isGuest)
    }

    // MARK: - Completion card

    /// 完成度, from the same module 首頁's hero reads. This card used to carry
    /// its own copy of the rule, and the copy was the pre-fix one: it fell back
    /// to the whole dictionary when the selected themes held no published
    /// cards, and it had no guest branch at all, so a guest who had learned 37
    /// words read 「0% · 已學 0 / 共 480 字」 while 首頁 said 37 / 480.
    /// Reading the stores here is also what registers the observation that
    /// re-renders this card when any of them changes — which is why the six
    /// stores are handed to the mapping rather than fetched by it. 首頁 builds
    /// its `TodayDecisions.Inputs.completion` from the same initializer.
    private var completion: CompletionReadout {
        CompletionReadout(
            .init(
                viewer: self.auth,
                settings: self.settings,
                progress: self.progress,
                words: self.words,
                cache: self.cache
            )
        )
    }

    private var completionCard: some View {
        let readout = self.completion
        let learned = readout.seen
        let total = readout.total
        // Both this stat and its detail line are scoped to the user's
        // selected 學習主題 (empty selection = all categories), same as the
        // 明細 breakdown below. Label it explicitly so it doesn't read as a
        // whole-catalog number next to Me tab's unscoped 已學字 total.
        let scoped = readout.scope != .wholeDictionary
        // The one number on this tab that is *the* number, so it gets the ink
        // block — the same weight the Today hero and the completion screen use.
        return VStack(alignment: .leading, spacing: Space.s2) {
            Text(scoped ? LocalizedStringKey("所選主題完成度") : LocalizedStringKey("圖鑑完成度"))
                .font(.tujiLabel)
                .tracking(0.5)
                .foregroundStyle(.tujiPaper.opacity(0.6))
            Text("\(readout.percent)%")
                .font(.tujiDisplay)
                .foregroundStyle(.tujiAccumulationSoft)
                .contentTransition(.numericText())
            Text(
                scoped
                    ? LocalizedStringKey("已學 \(learned) / 所選主題共 \(total) 字")
                    : LocalizedStringKey("已學 \(learned) / 共 \(total) 字")
            )
            .font(.tujiBodySm)
            .foregroundStyle(.tujiPaper.opacity(0.7))
            TujiProgressBar(
                progress: readout.ratio,
                track: .tujiPaper.opacity(0.15),
                fill: .tujiAccumulationSoft
            )
            .padding(.top, Space.s2)
        }
        .padding(Space.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.tujiInk)
    }

    // MARK: - Mastery distribution (熟練度)

    private var distribution: MasteryDistribution {
        MasteryDistribution.of(scores: self.mastery.byId)
    }

    /// 精通 as the headline, the spread as the evidence.
    ///
    /// On paper, with no ink block: the 完成度 card above is "the one number on
    /// this tab", and a second dark slab would leave the screen with two of
    /// them and no hierarchy. The count borrows `streakColumn`'s shape instead,
    /// which is what the tab already uses for a plain accumulated fact.
    private var masterySection: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            Text("熟練度")
                .font(.tujiLabel)
                .tracking(0.5)
                .foregroundStyle(.tujiInk3)
            self.masteryBody
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Three states, and the middle one is the reason this is not a plain
    /// `isEmpty` branch.
    ///
    /// An empty score map means "nothing studied" only *after* the store has
    /// answered. Before that it means "not known yet", and rendering
    /// 「還沒有學習紀錄」 over it states something about the account that may be
    /// false — on a slow network, for exactly the long-standing user this
    /// section exists to reassure. So an unanswered store draws the bar's track
    /// and says nothing. A guest is different again: their store is never
    /// warmed (`AccumulationSurface.needs` drops it), so waiting on `loaded`
    /// would leave them on that track forever.
    @ViewBuilder
    private var masteryBody: some View {
        if self.auth.isGuest {
            self.masteryNotice("登入後顯示熟練度")
        } else if !self.mastery.loaded {
            MasteryStackedBar(distribution: .empty)
        } else {
            let spread = self.distribution
            if spread.isEmpty {
                self.masteryNotice("還沒有學習紀錄")
            } else {
                self.expertHeadline(spread.expert)
                MasteryStackedBar(distribution: spread)
                self.masteryLegend(spread)
            }
        }
    }

    private func masteryNotice(_ message: LocalizedStringKey) -> some View {
        Text(message)
            .font(.tujiLabel)
            .foregroundStyle(.tujiInk3)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.vertical, Space.s3)
    }

    /// The prestige tier, counted. Same shape as `streakColumn` — label, display
    /// number, unit — because it is the same kind of fact about the account.
    private func expertHeadline(_ count: Int) -> some View {
        VStack(alignment: .leading, spacing: Space.s1) {
            Text(MasteryLevel.expert.name)
                .font(.tujiLabel)
                .tracking(0.5)
                .foregroundStyle(.tujiInk3)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("\(count)")
                    .font(.tujiDisplay)
                    .foregroundStyle(.tujiInk)
                    .contentTransition(.numericText())
                Text(verbatim: tujiLocalized("字"))
                    .font(.tujiBodySm)
                    .foregroundStyle(.tujiInk3)
            }
        }
    }

    /// Swatch + tier + count, one per tier, in ladder order — two columns, read
    /// left to right and then down, so the ladder order survives the wrap.
    ///
    /// Two columns rather than the heatmap legend's single row, because the
    /// four tiers do not fit on one line outside 繁中: measured at
    /// `tujiLabel` 13pt, the English row needs 387pt against 354pt on an
    /// iPhone 17 Pro, and the Japanese row overflows an iPhone SE. Development
    /// happens in 繁中 and CI runs English, which is precisely the pairing that
    /// ships an overflow nobody saw. Split in two, the widest cell in any of
    /// the four languages is 103pt against 155pt on the narrowest phone.
    private func masteryLegend(_ spread: MasteryDistribution) -> some View {
        LazyVGrid(
            columns: [
                GridItem(.flexible(), spacing: Space.s3, alignment: .leading),
                GridItem(.flexible(), spacing: Space.s3, alignment: .leading)
            ],
            alignment: .leading,
            spacing: Space.s2
        ) {
            ForEach(spread.segments) { segment in
                HStack(spacing: Space.s1) {
                    Rectangle()
                        .fill(segment.level.background)
                        .frame(width: 8, height: 8)
                    Text(segment.level.name)
                        .font(.tujiLabel)
                        .foregroundStyle(.tujiInk3)
                    Text("\(segment.words)")
                        .font(.tujiMono)
                        .foregroundStyle(.tujiInk2)
                        .contentTransition(.numericText())
                    Spacer(minLength: 0)
                }
            }
        }
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
            title: self.auth.isGuest ? "登入後才能看活躍熱力圖" : "還沒有學習紀錄",
            compact: true
        )
    }

    // MARK: - Category breakdown (明細)

    /// Per-category seen/total from the server, named + ordered via
    /// CategoriesStore. Categories with no published cards are dropped.
    /// Scoped to the user's selected study categories (empty = all) so the
    /// breakdown matches the completion card above. Falls back to raw
    /// progress rows if the category list hasn't loaded.
    private var categoryStats: [CategoryStat] {
        CategoryStat.breakdown(
            progress: self.progress.categoryProgress,
            selected: self.settings.current.studyCategories,
            categoryOrder: self.categories.categories
        )
    }

    private var emptyBreakdownMessage: LocalizedStringKey {
        if self.auth.isGuest { return "登入後顯示分類進度" }
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
            TujiProgressBar(progress: stat.ratio, track: .tujiPaper3, fill: .tujiAccumulation)
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
                    .font(.tujiLabel)
                    .foregroundStyle(.tujiInk3)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private var legend: some View {
        HStack(spacing: 6) {
            Text("少")
                .font(.tujiLabel)
                .foregroundStyle(.tujiInk3)
            ForEach(HeatmapBand.allCases, id: \.self) { band in
                RoundedRectangle(cornerRadius: 3)
                    .fill(band.tint)
                    .frame(width: 14, height: 14)
            }
            Text("多")
                .font(.tujiLabel)
                .foregroundStyle(.tujiInk3)
            Spacer()
        }
    }

    private func color(for cell: HeatmapCell) -> Color {
        if cell.future { return .tujiPaper }
        return HeatmapBand(count: cell.count).tint
    }
}

/// How many answers a day's cell stands for, as one of four steps.
///
/// It was two `private func`s on the grid — `strength(for:)` mapped a count to
/// `0…3` and `tintForLevel(_:)` mapped that to a colour, and the second one
/// returned `.tujiAccumulation` for both `2` and its `default`. So 5–12 and 13+
/// drew the same swatch, and the legend — which walks the levels rather than
/// listing colours — printed that swatch twice. `.tujiAccumulationDeep` is the
/// darkest step of the same ramp and already existed; the ramp stopped one short.
///
/// A value, not two functions on a `View`: the four bands and the four colours
/// are the whole content of the heatmap's legend, and nothing could reach them.
enum HeatmapBand: Int, CaseIterable {
    case none, light, medium, heavy

    init(count: Int) {
        switch count {
        case ..<1: self = .none
        case 1...4: self = .light
        case 5...12: self = .medium
        default: self = .heavy
        }
    }

    var tint: Color {
        switch self {
        case .none: .tujiPaper3
        case .light: .tujiAccumulationSoft
        case .medium: .tujiAccumulation
        case .heavy: .tujiAccumulationDeep
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
            .environment(MasteryStore.shared)
    }
}
