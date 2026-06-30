// Review-complete celebration (§III.R Complete). Shown after ReviewFlow
// finishes — Mascot cheer, reviewed-count display, streak +1 capsule, and a
// per-word 熟練度變化 list (before → after, with ↑ when the word crossed into a
// higher MasteryLevel). Reviews are deliberately NOT counted against the daily
// goal (that target tracks new words only — see TodayView.dailyGoalProgress /
// studyStats.todayNew), so this screen frames itself as "復習完成" rather than
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
    /// Ratings whose SRS write never reached the server (e.g. offline). Shown as
    /// a gentle notice so a silently dropped answer doesn't look fully saved.
    var unsyncedCount: Int = 0
    let onFinish: () -> Void

    @Environment(ProgressStore.self) private var progress
    @Environment(StudyStatsStore.self) private var studyStats
    @Environment(MasteryStore.self) private var mastery
    @Environment(SettingsStore.self) private var settings

    private var done: Int {
        self.answered.count
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: Space.s5) {
                    self.hero
                    self.streakCapsule
                    self.unsyncedNotice
                    self.changeSection
                }
                .padding(.horizontal, Space.s6)
                .padding(.top, Space.s12)
                .padding(.bottom, Space.s5)
            }
            self.footer
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.tujiBg)
        .task { await self.refresh() }
    }

    // MARK: - Bits

    private var hero: some View {
        MascotCelebrationCard(title: "複習完成！", accent: .tujiYellow) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("\(self.done)")
                    .font(.tujiDisplay)
                    .foregroundStyle(.tujiTeal)
                    .contentTransition(.numericText())
                Text("個字")
                    .font(.tujiH2)
                    .foregroundStyle(.tujiInk3)
            }
        }
    }

    private var streakCapsule: some View {
        HStack(spacing: Space.s2) {
            Image(systemName: "flame.fill")
                .foregroundStyle(.tujiCoral)
            if let streak = self.progress.streak?.current {
                Text("連勝 \(streak) 天")
                    .font(.system(size: 15, weight: .heavy))
                    .foregroundStyle(.tujiInk)
                    .contentTransition(.numericText())
            } else {
                Text("讀取連勝中…")
                    .font(.tujiCaption)
                    .foregroundStyle(.tujiInk3)
            }
        }
        .padding(.horizontal, Space.s4)
        .padding(.vertical, Space.s3)
        .background(.tujiCoral.opacity(0.12), in: .capsule)
        .overlay(Capsule().stroke(.tujiCoral.opacity(0.5), lineWidth: 1))
    }

    @ViewBuilder
    private var unsyncedNotice: some View {
        if self.unsyncedCount > 0 {
            HStack(spacing: Space.s2) {
                Image(systemName: "icloud.slash")
                    .foregroundStyle(.tujiCoral)
                Text("有 \(self.unsyncedCount) 筆評分未能同步，連上網路後請再複習一次。")
                    .font(.tujiCaption)
                    .foregroundStyle(.tujiInk2)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(Space.s3)
            .background(.tujiCoral.opacity(0.12), in: .rect(cornerRadius: Radius.md))
        }
    }

    @ViewBuilder
    private var changeSection: some View {
        if !self.answered.isEmpty {
            VStack(alignment: .leading, spacing: Space.s3) {
                Text("今天複習")
                    .font(.tujiOverline)
                    .tracking(2)
                    .foregroundStyle(.tujiTeal)
                VStack(spacing: Space.s2) {
                    ForEach(self.answered) { item in
                        self.changeRow(item)
                    }
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
                    .font(.system(size: 15, weight: .heavy))
                    .foregroundStyle(.tujiInk)
                    .lineLimit(1)
                if self.settings.current.showZh {
                    Text(item.word.chinese)
                        .font(.tujiCaption)
                        .foregroundStyle(.tujiInk3)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: Space.s2)
            if let change {
                VStack(alignment: .trailing, spacing: 3) {
                    HStack(spacing: 4) {
                        if leveledUp {
                            Image(systemName: "arrow.up")
                                .font(.system(size: 10, weight: .black))
                                .foregroundStyle(.tujiGreen)
                        }
                        self.levelPill(afterLevel)
                    }
                    HStack(spacing: 4) {
                        Text("\(change.before)→\(change.after)")
                            .font(.tujiCaption)
                            .foregroundStyle(.tujiInk3)
                            .contentTransition(.numericText())
                        Text(self.deltaText(change.delta))
                            .font(.system(size: 12, weight: .heavy))
                            .foregroundStyle(self.deltaColor(change.delta))
                    }
                }
            }
        }
        .padding(Space.s2)
        .frame(maxWidth: .infinity)
        .background(.tujiCard, in: .rect(cornerRadius: Radius.md))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md)
                .stroke(.tujiInk4.opacity(0.15), lineWidth: 1)
        )
    }

    private func thumb(_ word: StudyQueueWord) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: Radius.sm).fill(.tujiCard)
            LazyImage(url: word.imageURL) { state in
                if let image = state.image {
                    image.resizable().aspectRatio(contentMode: .fit).padding(4)
                } else if state.error != nil {
                    Image(systemName: "photo").font(.system(size: 14)).foregroundStyle(.tujiInk4)
                } else {
                    ProgressView().tint(.tujiTeal)
                }
            }
            .pipeline(.shared)
        }
        .frame(width: 44, height: 44)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.sm)
                .stroke(.tujiInk4.opacity(0.2), lineWidth: 1)
        )
    }

    private func levelPill(_ level: MasteryLevel) -> some View {
        Text(level.name)
            .font(.system(size: 11, weight: .heavy))
            .foregroundStyle(level.color)
            .padding(.horizontal, Space.s2)
            .padding(.vertical, 2)
            .background(level.color.opacity(0.14), in: .capsule)
    }

    private func deltaText(_ d: Int) -> String {
        d > 0 ? "+\(d)" : "\(d)"
    }

    private func deltaColor(_ d: Int) -> Color {
        if d > 0 { return .tujiGreen }
        if d < 0 { return .tujiCoral }
        return .tujiInk3
    }

    private var footer: some View {
        BBtn(
            title: "回首頁",
            bg: .tujiTeal,
            fg: .white,
            fullWidth: true,
            icon: "house.fill",
            action: self.onFinish
        )
        .padding(.horizontal, Space.s6)
        .padding(.vertical, Space.s4)
        .background(.tujiBg)
    }

    private func refresh() async {
        // Force round trips — streak, due/seen counts, and per-word mastery
        // all just changed on the answer POST, and we want fresh values here
        // and on the 圖鑑/詳情 the user returns to.
        self.progress.invalidate()
        self.studyStats.invalidate()
        self.mastery.invalidate()
        // Drop any prefetched queue — this session changed due/seen counts, so
        // the next 復習 / 學新字 must re-fetch rather than reuse a stale queue.
        StudyQueueStore.shared.invalidate()
        async let p: Void = self.progress.reload()
        async let s: Void = self.studyStats.reload()
        async let m: Void = self.mastery.reload()
        await p
        await s
        await m
    }
}

#Preview {
    CompleteView(answered: [], masteryByWord: [:], onFinish: {})
        .environment(ProgressStore.shared)
        .environment(StudyStatsStore.shared)
        .environment(MasteryStore.shared)
        .environment(SettingsStore.shared)
}
