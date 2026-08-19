// ReviewFlow root (§III.Q). MCQ surface on top, slide-in footer with
// SRS rating buttons on the bottom once the user picks. Each item runs
// answer → reveal → rate → next.

import Nuke
import NukeUI
import OSLog
import Observation
import SwiftUI

struct ReviewFlowView: View {
    let queue: [StudyQueueItem]
    @State private var coord: ReviewFlowCoordinator
    @Environment(\.dismiss) private var dismiss
    @Environment(StudyFocus.self) private var studyFocus
    @Environment(SettingsStore.self) private var settings
    @State private var showExitConfirm = false
    /// Latched when the user confirms leaving, so the reveal sheet stays down
    /// through the pop instead of flashing back up when the confirm closes.
    @State private var leaving = false
    @State private var reportDraft: StudyReportDraft?
    @State private var showCustomCardNotice = false
    /// Set when the post-session refresh lands. CompleteView's 還有 N 個 CTA
    /// waits for it — before that round-trip the store holds the pre-session
    /// due count.
    @State private var sessionRefreshed = false

    init(queue: [StudyQueueItem]) {
        self.queue = queue
        self._coord = State(initialValue: ReviewFlowCoordinator(queue: queue))
    }

    var body: some View {
        Group {
            if self.coord.finished {
                // The refresh hangs off the finish, not off whichever screen
                // celebrates it — a milestone session used to refresh nothing.
                self.finishedSurface
                    .refreshesFinishedSession(draining: self.coord.writes) {
                        self.sessionRefreshed = true
                    }
            } else {
                self.flowSurface
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationBarBackButtonHidden(true)
        // The bar is drawn in the content (`flowSurface`), not by the system:
        // on iOS 26 a toolbar item is a floating glass circle, and two white
        // discs at the top of a study screen are the platform talking over it.
        .toolbar(.hidden, for: .navigationBar)
        .tujiPrompt(
            isPresented: self.$showExitConfirm,
            style: .confirmation,
            title: "要離開這次複習嗎？",
            message: "已答的進度會保留，未完成的字下次還會出現。",
            primary: TujiPromptAction("先離開") {
                // Drop the scheduled advance first, or it fires after teardown.
                // Then drop the reveal sheet (and keep it down), then leave.
                self.coord.cancelPendingBeats()
                self.leaving = true
                self.dismiss()
            },
            secondary: TujiPromptAction("繼續複習", role: .cancel) {}
        )
        .tujiPrompt(
            isPresented: self.$showCustomCardNotice,
            style: .confirmation,
            title: "自制卡片暫不支援報錯",
            message: "報錯僅適用於官方單字內容。自制卡片如有問題，可以到自制圖鑑刪除重拍，或透過「我的」頁的意見收集告訴我們。",
            primary: TujiPromptAction("知道了") {}
        )
        .onAppear {
            self.studyFocus.enter()
            AnalyticsService.shared.track(.studyStart, category: "review")
        }
        .onDisappear { self.studyFocus.exit() }
        .fullScreenCover(item: self.$reportDraft) { draft in
            StudyReportSheet(draft: draft)
        }
    }

    /// Which celebration a finished session shows. A streak milestone wins:
    /// it happens at most a few times a year and the summary is always one tap
    /// away behind it.
    @ViewBuilder
    private var finishedSurface: some View {
        if let milestone = coord.writes.milestone {
            MilestoneView(milestone: milestone, onFinish: { self.dismiss() })
                .onAppear { AnalyticsService.shared.track(.studyComplete, category: "review") }
        } else {
            CompleteView(
                answered: self.coord.answered,
                masteryByWord: self.coord.writes.masteryByWord,
                wrongIds: self.coord.retriedIds,
                unsyncedCount: self.coord.writes.parkedCount,
                onFinish: { self.dismiss() },
                onAnotherRound: { await self.startAnotherRound() },
                refreshed: self.sessionRefreshed
            )
            .onAppear { AnalyticsService.shared.track(.studyComplete, category: "review") }
        }
    }

    /// 再來一輪 from CompleteView: fetch a fresh due queue (via the coordinator's
    /// injected queue provider) and restart the flow with a clean coordinator —
    /// the swap resets `finished`, so the surface flips back to the question view
    /// without re-navigating.
    private func startAnotherRound() async {
        let queue = await self.coord.fetchAnotherRound()
        guard !queue.isEmpty else { return }
        self.coord = ReviewFlowCoordinator(queue: queue)
    }

    private func captureReport() {
        guard let item = self.coord.current else { return }
        // Custom cards have no cards-table row, so /api/study/reports
        // can't accept them — explain instead of silently dropping the tap.
        guard !item.card.id.hasPrefix("atlas:") else {
            self.showCustomCardNotice = true
            return
        }
        self.reportDraft = StudyReportDraft(
            item: item,
            mode: "review",
            phase: self.coord.phase == .answer ? "answer" : "reveal",
            selectedAnswer: self.coord.picked,
            uiLang: self.settings.current.uiLang
        )
    }

    private var flowSurface: some View {
        GeometryReader { geo in
            VStack(spacing: 0) {
                TujiNavBar(leading: .close, onLeading: { self.showExitConfirm = true }) {
                    Menu {
                        Button("報錯", systemImage: "exclamationmark.bubble") {
                            self.captureReport()
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.tujiIcon(19, weight: .semibold))
                            .foregroundStyle(.tujiInk)
                            .frame(width: 44, height: 48)
                            .contentShape(.rect)
                    }
                    .accessibilityLabel(Text("更多"))
                }
                self.header
                if let item = coord.current {
                    ReviewQuestionView(
                        coord: self.coord,
                        item: item,
                        heroHeight: self.heroHeight(in: geo)
                    )
                } else {
                    Spacer()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            // Keep the MCQ option recolour on pick smooth (previously carried
            // by the footer's ZStack animation).
            .animation(.spring(duration: 0.35), value: self.coord.phase)
            .background(.tujiPaper)
            // MainTabsView normally reserves 78pt for the custom TujiTabBar;
            // that ancestor inset doesn't propagate into pushed views, so we
            // mirror it. In study mode (StudyFocus.active) both the bar and
            // its reservation go away — drop the local mirror too.
            .safeAreaInset(edge: .bottom, spacing: 0) {
                Color.clear.frame(height: self.studyFocus.active ? 0 : 78)
            }
            // Flash capsule for the no-sheet paths (auto-rated fast correct /
            // passed retest) so the write is still visibly acknowledged.
            .overlay(alignment: .bottom) {
                if let flash = self.coord.flash {
                    ReviewFlashCapsule(flash: flash)
                        .padding(.bottom, Space.s5)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.spring(duration: 0.3), value: self.coord.flash)
            // The reveal (summary + full-detail pull-up + SRS rating) rides up
            // as a detent sheet, mirroring the new-word peek sheet. Raised only
            // when the answer needs the user (wrong, or correct-but-slow) —
            // fast correct answers auto-rate and skip it entirely. Rating (or
            // 下一題 on a retest) advances the queue → revealMode clears → the
            // sheet dismisses on its own. Not swipe-dismissable.
            //
            // Hide it while the exit-confirm prompt is up: the rest detent
            // leaves the toolbar ✕ tappable (presentationBackgroundInteraction),
            // so tapping it during reveal would otherwise stack the confirm
            // behind this sheet and bury both sets of buttons. The sheet
            // returns if the user taps 繼續複習.
            .sheet(isPresented: Binding(
                get: {
                    self.coord.revealMode != nil && !self.coord.finished
                        && !self.showExitConfirm && !self.leaving
                },
                set: { _ in }
            )) {
                if let item = self.coord.current {
                    ReviewRevealSheet(coord: self.coord, item: item)
                }
            }
        }
    }

    /// Hero height adapts to the device. In study mode the tab bar is
    /// hidden (PR #46) so we have ~78pt more headroom and the cap pushes
    /// up to 360pt — image details (rice grains, bottle profiles) become
    /// legible. Normal mode keeps PR #45's 280 cap.
    private func heroHeight(in geo: GeometryProxy) -> CGFloat {
        // Fixed costs other than the hero, sized to the smaller of
        //   - study mode: tab inset 0, scroll-bottom s4 (16)
        //   - normal mode: tab inset 78, scroll-bottom s24 (96)
        let active = self.studyFocus.active
        let tabInset: CGFloat = active ? 0 : 78
        let scrollBottom: CGFloat = active ? 16 : 96
        // nav bar 56 + header 47 + s3 spacing 16 + 4 choices (4×64 + 3×8) 280
        // + slack 20. The bar counts now: it is drawn inside this GeometryReader
        // rather than taken out of the safe area by the system toolbar.
        let baseReserved: CGFloat = 419
        let reserved = baseReserved + tabInset + scrollBottom
        let available = geo.size.height - reserved
        return min(active ? 360 : 280, max(200, available))
    }

    /// 複習 in 墨3, not teal: teal means accumulation, and a mode label
    /// accumulates nothing. The count is `tujiMono` so the digits hold their
    /// width — a proportional 1 next to a 7 makes the number jitter as it
    /// climbs, which reads as the layout moving rather than the count.
    private var header: some View {
        VStack(spacing: Space.s2) {
            HStack {
                Text("複習")
                    .font(.tujiLabel)
                    .tracking(0.5)
                    .foregroundStyle(.tujiInk3)
                Spacer()
                Text("\(self.coord.passedCount) / \(self.coord.originalCount)")
                    .font(.tujiMono)
                    .foregroundStyle(.tujiInk2)
                    .contentTransition(.numericText())
            }
            .padding(.horizontal, Space.s4)

            TujiProgressBar(progress: self.coord.progress)
        }
        .padding(.bottom, Space.s3)
    }
}

// MARK: - Question (image + bubble + 4 options)

private struct ReviewQuestionView: View {
    let coord: ReviewFlowCoordinator
    let item: StudyQueueItem
    let heroHeight: CGFloat

    @Environment(StudyFocus.self) private var studyFocus
    @Environment(WordsStore.self) private var words
    @Environment(\.targetLanguage) private var session

    /// The cat used to sit here on *every* question asking 這個是什麼？, with its
    /// pose switching to cheer once the combo hit three. C.11 allows the mascot
    /// at four moments only, and "each of the thirty cards in a session" is not
    /// one of them — a character who reacts to every tap is the reward loop this
    /// design rules out, and the prompt was answering a question nobody had (an
    /// image above four words is self-evident). The 56pt it occupied goes to the
    /// picture. The question survives for VoiceOver as the image's label.
    var body: some View {
        ScrollView {
            VStack(spacing: Space.s3) {
                ReviewHeroCard(coord: self.coord, item: self.item, height: self.heroHeight)
                self.choicesList
                    .padding(.horizontal, Space.s4)
            }
            // PR #46: in study mode the tab bar is gone so we can trim the
            // big s24 scroll buffer that previously kept the footer clear.
            .padding(.bottom, self.studyFocus.active ? Space.s3 : Space.s6)
        }
    }

    private var choicesList: some View {
        StudyChoiceList(
            item: self.item,
            variant: self.coord.choicesVariant(for: self.item),
            picked: self.coord.picked,
            revealed: self.coord.phase == .review
        ) { self.coord.pick($0) }
    }
}

// MARK: - Flash capsule (auto-rated / retest passed)

/// Bottom capsule acknowledging an answer that advanced without the reveal
/// sheet: fast correct answers show the auto-applied rating, passed retests a
/// plain 答對了. Visible for the ~700ms advance beat.
private struct ReviewFlashCapsule: View {
    let flash: ReviewFlash

    var body: some View {
        HStack(spacing: Space.s2) {
            Image(systemName: "checkmark.circle.fill")
                .font(.tujiIcon(15, weight: .semibold))
            Text(self.label)
                .font(.tujiIcon(15, weight: .semibold))
        }
        .foregroundStyle(.white)
        .padding(.horizontal, Space.s4)
        .padding(.vertical, Space.s3)
        .background(self.tint, in: .rect(cornerRadius: Radius.r0))
        .shadow(color: .black.opacity(0.15), radius: 8, y: 3)
    }

    private var label: LocalizedStringKey {
        switch self.flash {
        case let .autoRated(rating): rating.label
        case .retestPassed: "答對了"
        }
    }

    private var tint: Color {
        switch self.flash {
        case let .autoRated(rating):
            switch rating {
            case .again: .tujiAlert
            case .hard: .tujiCurrent
            case .good: .tujiAccumulation
            case .easy: .tujiAccumulation
            }
        case .retestPassed: .tujiAccumulation
        }
    }
}
