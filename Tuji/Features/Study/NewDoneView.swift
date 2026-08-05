// Completion celebration shown after Step 3 wraps. Lists the words
// learned this session and a 完成 CTA back to the previous screen.

import Nuke
import NukeUI
import SwiftUI

struct NewDoneView: View {
    let coord: NewFlowCoordinator
    let queue: [StudyQueueItem]
    let onFinish: () -> Void

    @Environment(MasteryStore.self) private var mastery
    @Environment(StudyStatsStore.self) private var studyStats
    @Environment(ProgressStore.self) private var progress

    var body: some View {
        ScrollView {
            VStack(spacing: Space.s4) {
                self.hero
                UnsyncedAnswersNotice(unsyncedCount: self.coord.parkedCount)
                    .padding(.horizontal, Space.s4)
                StudyWordGrid(items: self.queue, mistakeCounts: self.coord.mistakeCounts)
            }
            .padding(.bottom, Space.s5)
        }
        // Learning new words writes mastery + creates user_cards + study_logs
        // (the deferred recognize POSTs fired as each word cleared Spell).
        // Reload — not just invalidate — every store the home surfaces read:
        // Today stays mounted under this push, so its .task won't re-run on
        // pop, and an invalidated-but-unreloaded store leaves 今日目標 0/10 and
        // the streak flame at 0 right after the session (until a tab swap).
        .task {
            await SessionRefresh(
                stores: [self.mastery, self.studyStats, self.progress],
                invalidateQueue: { StudyQueueStore.shared.invalidate() }
            ).run(draining: self.coord)
        }
        .safeAreaInset(edge: .bottom) {
            BBtn(
                title: "完成",
                bg: .tujiEye,
                fg: .tujiInk,
                fullWidth: true,
                icon: "checkmark",
                action: self.onFinish
            )
            .padding(.horizontal, Space.s4)
            .padding(.bottom, Space.s3)
        }
    }

    private var hero: some View {
        MascotCelebrationCard(title: "這節學了 \(self.queue.count) 個新字") {
            Text("它們已加入你的圖鑑")
                .font(.tujiBodySm)
                .foregroundStyle(.tujiPaper.opacity(0.7))
        }
        .padding(.top, Space.s5)
    }
}

/// Shown on both completion screens (new-word and review) when some SRS
/// ratings couldn't be sent and were parked in the durable outbox (offline /
/// server down). They replay automatically on the next launch/foreground, so
/// this is reassurance, not an error. Hidden when `count` is 0.
struct UnsyncedAnswersNotice: View {
    let unsyncedCount: Int

    var body: some View {
        if self.unsyncedCount > 0 {
            HStack(spacing: Space.s2) {
                Image(systemName: "icloud.slash")
                    .foregroundStyle(.tujiAlert)
                Text("有 \(self.unsyncedCount) 筆評分還沒送出，已排入待同步，連上網路後會自動補送。")
                    .font(.tujiLabel)
                    .foregroundStyle(.tujiInk2)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(Space.s3)
            .background(.tujiAlert.opacity(0.12), in: .rect(cornerRadius: Radius.r0))
        }
    }
}

/// Two-column word grid shown on the study-complete screens (new-word and
/// review), so both celebrate the session's words with the same tile style.
struct StudyWordGrid: View {
    let items: [StudyQueueItem]
    /// Session mistakes by word id; words with retries get a 答錯 badge so
    /// the recap points at what to watch. Empty (the default) shows none.
    var mistakeCounts: [String: Int] = [:]

    @Environment(SettingsStore.self) private var settings

    var body: some View {
        LazyVGrid(
            columns: [
                GridItem(.flexible(), spacing: Space.s2),
                GridItem(.flexible(), spacing: Space.s2)
            ],
            spacing: Space.s4
        ) {
            ForEach(self.items) { item in
                self.tile(for: item)
            }
        }
        .padding(.horizontal, Space.s4)
    }

    /// No card and no border (D.2). The tile used to be a bordered white box
    /// around a white-backdrop cut-out — two nested rectangles, both lighter
    /// than the page, framing a picture that was already the only thing there.
    /// The `tujiPaper2` square is the container now, and the picture multiplies
    /// into it, so what you see is the object and its name.
    private func tile(for item: StudyQueueItem) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Color.tujiPaper2
                .aspectRatio(1, contentMode: .fit)
                .overlay {
                    LazyImage(url: item.word.imageURL) { state in
                        if let image = state.image {
                            image.resizable()
                                .aspectRatio(
                                    contentMode: item.word.imageKind == .cutout ? .fit : .fill
                                )
                                .padding(item.word.imageKind == .cutout ? Space.s3 : 0)
                                .blendMode(item.word.imageKind == .cutout ? .multiply : .normal)
                        } else if state.error != nil {
                            Image(systemName: "photo")
                                .foregroundStyle(.tujiInk3)
                        } else {
                            TujiImagePlaceholder()
                        }
                    }
                    .pipeline(.shared)
                }
                .clipped()

            Text(item.word.word)
                .font(.tujiH3)
                .foregroundStyle(.tujiInk)
                .lineLimit(1)
                .padding(.top, Space.s2)
            if let wrongs = self.mistakeCounts[item.word.id], wrongs > 0 {
                TujiStatusEdgeLabel(text: Text("答錯 \(wrongs) 次"), edge: .tujiAlert)
                    .padding(.top, Space.s1)
            } else if self.settings.current.showZh {
                Text(item.word.chinese)
                    .font(.tujiBodySm)
                    .foregroundStyle(.tujiInk3)
                    .lineLimit(1)
                    .padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
