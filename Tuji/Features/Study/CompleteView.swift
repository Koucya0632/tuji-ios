// Review-complete celebration (§III.R Complete). Shown after ReviewFlow
// finishes — Mascot cheer, reviewed-count display, streak +1 capsule,
// answered tiles row, 回首頁 CTA. Reviews are deliberately NOT counted
// against the daily goal (that target tracks new words only — see
// TodayView.dailyGoalProgress / studyStats.todayNew), so this screen
// frames itself as "復習完成" rather than the daily-goal milestone.
//
// Streak comes from ProgressStore.shared. We invalidate first so the
// new entry from the just-answered session (which the server already
// busted on /api/study/answer) is round-tripped fresh instead of read
// from the 30s in-memory window.

import SwiftUI

struct CompleteView: View {
    let answered: [StudyQueueItem]
    let onFinish: () -> Void

    @Environment(ProgressStore.self) private var progress
    @Environment(StudyStatsStore.self) private var studyStats

    private var done: Int {
        self.answered.count
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: Space.s5) {
                    self.hero
                    self.streakCapsule
                    self.answeredSection
                }
                .padding(.horizontal, Space.s6)
                .padding(.top, Space.s12)
                .padding(.bottom, Space.s5)
            }
            self.footer
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.tujiBg)
        .task { await self.loadStreak() }
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
    private var answeredSection: some View {
        if !self.answered.isEmpty {
            VStack(alignment: .leading, spacing: Space.s3) {
                Text("今天複習")
                    .font(.tujiOverline)
                    .tracking(2)
                    .foregroundStyle(.tujiTeal)
                StudyWordGrid(items: self.answered)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
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

    private func loadStreak() async {
        // Force round trips — both streak and due/seen counts just changed
        // on the answer POST, and we want the new values shown here.
        self.progress.invalidate()
        self.studyStats.invalidate()
        async let p: Void = self.progress.reload()
        async let s: Void = self.studyStats.reload()
        await p
        await s
    }
}

#Preview {
    CompleteView(answered: [], onFinish: {})
        .environment(ProgressStore.shared)
        .environment(StudyStatsStore.shared)
}
