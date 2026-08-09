// Review-complete celebration (§III.R Complete). Shown after ReviewFlow
// finishes — Mascot cheer, reviewed-count display, streak +1 capsule, and a
// per-word 熟練度變化 list (before → after, with ↑ when the word crossed into a
// higher MasteryLevel). Reviews are deliberately NOT counted against the daily
// goal (that target tracks new words only — see TodayView.dailyGoalProgress /
// studyStats.todayNew), so this screen frames itself as "複習完成" rather than
// the daily-goal milestone.
//
// Streak comes from ProgressStore.shared; mastery scores from MasteryStore.
// We invalidate both first so the just-answered session (which the server
// already busted on /api/study/answer) is round-tripped fresh — the streak
// shows the new value here, and the 圖鑑/詳情 reflect the new scores when the
// user navigates back.

import Nuke
import NukeUI
import SwiftUI

struct CompleteView: View {
    let answered: [StudyQueueItem]
    let masteryByWord: [String: MasteryDelta]
    /// Words missed (and re-tested) this session — marked 答錯過 in the list.
    var wrongIds: Set<String> = []
    /// Ratings whose SRS write never reached the server (e.g. offline). Parked
    /// in StudyAnswerOutbox for auto-replay; shown as a gentle notice so the
    /// session doesn't silently look fully synced.
    var unsyncedCount: Int = 0
    let onFinish: () -> Void
    /// Starts a follow-up session when words are still due (再來一輪). nil
    /// hides the chaining CTA.
    var onAnotherRound: (() async -> Void)?
    /// The review coordinator, so the post-session refresh can drain its
    /// optimistic writes before reloading (mirrors NewDoneView). Defaults to a
    /// no-op drainer for previews.
    var draining: PendingWriteDraining = NoPendingWrites()

    @Environment(ProgressStore.self) private var progress
    @Environment(StudyStatsStore.self) private var studyStats
    @Environment(MasteryStore.self) private var mastery
    @Environment(SettingsStore.self) private var settings

    /// The remaining-due CTA waits for refresh(): before the round-trip the
    /// store still holds the pre-session due count.
    @State private var refreshed = false
    @State private var startingNextRound = false

    private var done: Int {
        self.answered.count
    }

    /// Words still due after this session (post-refresh). Drives the 再來一輪
    /// CTA — the full celebration is reserved for an actually-cleared queue,
    /// so "complete" never contradicts a still-lit 複習 button on Today.
    private var remainingDue: Int {
        guard self.refreshed else { return 0 }
        return self.studyStats.stats?.due ?? 0
    }

    private var hasMoreDue: Bool {
        self.remainingDue > 0 && self.onAnotherRound != nil
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: Space.s4) {
                    self.hero
                    self.streakLine
                        .padding(.horizontal, Space.s4)
                    self.unsyncedNotice
                        .padding(.horizontal, Space.s4)
                    self.changeSection
                }
                .padding(.top, Space.s5)
                .padding(.bottom, Space.s4)
            }
            self.footer
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.tujiPaper)
        .task { await self.refresh() }
    }

    // MARK: - Bits

    private var hero: some View {
        MascotCelebrationCard(title: self.hasMoreDue ? "這一輪完成" : "複習完成！") {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                // The pale teal step, not the deep one: 深 teal on ink is only
                // 3.04:1, and this is the biggest number on the screen.
                Text("\(self.done)")
                    .font(.tujiDisplay)
                    .foregroundStyle(.tujiAccumulationSoft)
                    .contentTransition(.numericText())
                Text("個字")
                    .font(.tujiH2)
                    .foregroundStyle(.tujiPaper.opacity(0.7))
            }
        }
    }

    /// A line, not a badge. The streak used to sit in a teal-tinted box with a
    /// teal border and a flame — three ways of shouting a number that is simply
    /// a fact about the account. It is accumulation, so it is teal, and that is
    /// the whole treatment.
    private var streakLine: some View {
        Group {
            if let streak = self.progress.streak?.current {
                HStack(spacing: Space.s2) {
                    Text("連勝")
                        .font(.tujiLabel)
                        .tracking(0.5)
                        .foregroundStyle(.tujiInk3)
                    Text("\(streak)")
                        .font(.tujiMono)
                        .foregroundStyle(.tujiAccumulation)
                        .contentTransition(.numericText())
                    Text("天")
                        .font(.tujiLabel)
                        .foregroundStyle(.tujiInk3)
                }
            } else {
                Text("讀取連勝中…")
                    .font(.tujiLabel)
                    .foregroundStyle(.tujiInk3)
            }
        }
    }

    private var unsyncedNotice: some View {
        UnsyncedAnswersNotice(unsyncedCount: self.unsyncedCount)
    }

    @ViewBuilder
    private var changeSection: some View {
        if !self.answered.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                Text("今天複習")
                    .font(.tujiLabel)
                    .tracking(0.5)
                    .foregroundStyle(.tujiInk3)
                    .padding(.horizontal, Space.s4)
                    .padding(.bottom, Space.s3)
                ForEach(Array(self.answered.enumerated()), id: \.element.id) { index, item in
                    if index > 0 {
                        Rectangle()
                            .fill(.tujiRule)
                            .frame(height: Border.bw1)
                            .padding(.leading, Space.s4)
                    }
                    self.changeRow(item)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func changeRow(_ item: StudyQueueItem) -> some View {
        let change = self.masteryByWord[item.word.id]
        let afterLevel = MasteryLevel.from(score: change?.after)
        let leveledUp = change.map {
            afterLevel.rawValue > MasteryLevel.from(score: $0.before).rawValue
        } ?? false

        return HStack(spacing: Space.s3) {
            self.thumb(item.word)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.word.word)
                    .font(.tujiH3)
                    .foregroundStyle(.tujiInk)
                    .lineLimit(1)
                if self.wrongIds.contains(item.word.id) {
                    TujiStatusEdgeLabel(text: Text("答錯過"), edge: .tujiAlert)
                        .padding(.top, 2)
                } else if self.settings.current.showZh {
                    Text(item.word.chinese)
                        .font(.tujiBodySm)
                        .foregroundStyle(.tujiInk3)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: Space.s2)
            if let change {
                VStack(alignment: .trailing, spacing: Space.s1) {
                    self.levelPill(afterLevel)
                    HStack(spacing: 4) {
                        // ↑ only, and only when the word actually crossed a
                        // level. The before→after pair is the evidence; the
                        // arrow says the crossing happened.
                        if leveledUp {
                            Image(systemName: "arrow.up")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(.tujiAccumulation)
                        }
                        Text("\(change.before)→\(change.after)")
                            .font(.tujiMono)
                            .foregroundStyle(.tujiInk3)
                            .contentTransition(.numericText())
                    }
                }
            }
        }
        .padding(.horizontal, Space.s4)
        .frame(minHeight: 72)
        .frame(maxWidth: .infinity)
    }

    private func thumb(_ word: StudyQueueWord) -> some View {
        Color.tujiPaper2
            .frame(width: 48, height: 48)
            .overlay {
                LazyImage(url: word.imageURL) { state in
                    if let image = state.image {
                        image.resizable()
                            .aspectRatio(contentMode: word.imageKind == .cutout ? .fit : .fill)
                            .padding(word.imageKind == .cutout ? Space.s1 : 0)
                            .blendMode(word.imageKind == .cutout ? .multiply : .normal)
                    } else if state.error != nil {
                        Image(systemName: "photo").font(.system(size: 14)).foregroundStyle(.tujiInk3)
                    } else {
                        TujiImagePlaceholder()
                    }
                }
                .pipeline(.shared)
            }
            .clipped()
    }

    private func levelPill(_ level: MasteryLevel) -> some View {
        Text(level.name)
            .font(.tujiLabel)
            .tracking(0.5)
            .foregroundStyle(level.foreground)
            .padding(.horizontal, Space.s2)
            .padding(.vertical, 2)
            .background(level.background, in: .rect(cornerRadius: Radius.r0))
    }

    /// 回首頁 when the queue is clear; when words are still due, the primary
    /// action chains straight into the next round so clearing a backlog is a
    /// tap, not a round-trip through Today.
    private var footer: some View {
        VStack(spacing: Space.s2) {
            if self.hasMoreDue {
                BBtn(
                    title: self.startingNextRound
                        ? "載入下一輪…"
                        : "再來一輪（還有 \(self.remainingDue) 字）",
                    bg: .tujiBrandPrimary,
                    fg: .tujiInk,
                    fullWidth: true,
                    icon: "arrow.clockwise"
                ) {
                    guard !self.startingNextRound else { return }
                    Task {
                        self.startingNextRound = true
                        defer { self.startingNextRound = false }
                        await self.onAnotherRound?()
                    }
                }
                .disabled(self.startingNextRound)
                Button(action: self.onFinish) {
                    Text("先到這裡，回首頁")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.tujiInk3)
                        .padding(.vertical, Space.s2)
                }
                .buttonStyle(.plain)
            } else {
                BBtn(
                    title: "回首頁",
                    bg: .tujiBrandPrimary,
                    fg: .tujiInk,
                    fullWidth: true,
                    icon: "house.fill",
                    action: self.onFinish
                )
            }
        }
        .padding(.horizontal, Space.s4)
        .padding(.vertical, Space.s3)
        .background(.tujiPaper)
    }

    private func refresh() async {
        // Same drain → invalidate → reload as NewDoneView, via the shared home:
        // streak, due/seen counts, and per-word mastery all just changed on the
        // answer POST, and we want fresh values here and on the 圖鑑/詳情 the user
        // returns to. Draining first (which review didn't used to do) keeps the
        // reload from racing the last answer's write.
        await SessionRefresh(
            stores: [self.mastery, self.studyStats, self.progress],
            invalidateQueue: { StudyQueueStore.shared.invalidate() }
        ).run(draining: self.draining)
        self.refreshed = true
    }
}

#Preview {
    CompleteView(answered: [], masteryByWord: [:], onFinish: {})
        .environment(ProgressStore.shared)
        .environment(StudyStatsStore.shared)
        .environment(MasteryStore.shared)
        .environment(SettingsStore.shared)
}
