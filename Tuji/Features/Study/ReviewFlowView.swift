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

    init(queue: [StudyQueueItem]) {
        self.queue = queue
        self._coord = State(initialValue: ReviewFlowCoordinator(queue: queue))
    }

    var body: some View {
        Group {
            if self.coord.finished {
                if let m = coord.milestone {
                    MilestoneView(milestone: m, onFinish: { self.dismiss() })
                        .onAppear { AnalyticsService.shared.track(.studyComplete, category: "review") }
                } else {
                    CompleteView(
                        answered: self.coord.answered,
                        masteryByWord: self.coord.masteryByWord,
                        wrongIds: self.coord.retriedIds,
                        unsyncedCount: self.coord.unsyncedCount,
                        onFinish: { self.dismiss() },
                        onAnotherRound: { await self.startAnotherRound() }
                    )
                    .onAppear { AnalyticsService.shared.track(.studyComplete, category: "review") }
                }
            } else {
                self.flowSurface
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationBarBackButtonHidden(true)
        .toolbar(self.coord.finished ? .hidden : .visible, for: .navigationBar)
        .toolbar {
            if !self.coord.finished {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        self.showExitConfirm = true
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.tujiInk2)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("報錯", systemImage: "exclamationmark.bubble") {
                            self.captureReport()
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(.tujiInk2)
                            .frame(width: 36, height: 36)
                    }
                }
            }
        }
        .tujiPrompt(
            isPresented: self.$showExitConfirm,
            style: .confirmation,
            title: "要離開這次複習嗎？",
            message: "已答的進度會保留，未完成的字下次還會出現。",
            primary: TujiPromptAction("先離開") {
                // Drop the reveal sheet first (and keep it down), then leave.
                self.leaving = true
                self.dismiss()
            },
            secondary: TujiPromptAction("繼續複習", role: .cancel) {}
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

    /// 再來一輪 from CompleteView: fetch a fresh due queue and restart the
    /// flow in place (the coordinator swap resets `finished`, so the surface
    /// flips back to the question view without re-navigating).
    private func startAnotherRound() async {
        guard let queue = try? await StudyQueueStore.shared.fetch(mode: .review),
              !queue.isEmpty
        else { return }
        self.coord = ReviewFlowCoordinator(queue: queue)
    }

    private func captureReport() {
        guard let item = self.coord.current, !item.card.id.hasPrefix("atlas:") else { return }
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
            .background(.tujiBg)
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
                        .padding(.bottom, Space.s10)
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
        // toolbar 44 + header 50 + bubble 56 + 2× s4 spacing 32
        // + 4 choices 216 + slack 20
        let baseReserved: CGFloat = 418
        let reserved = baseReserved + tabInset + scrollBottom
        let available = geo.size.height - reserved
        return min(active ? 360 : 280, max(200, available))
    }

    private var header: some View {
        VStack(spacing: Space.s3) {
            HStack {
                Text("複習")
                    .font(.tujiOverline)
                    .tracking(2)
                    .foregroundStyle(.tujiTeal)
                Spacer()
                Text("\(self.coord.passedCount) / \(self.coord.originalCount)")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.tujiInk3)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(.tujiInk4.opacity(0.2))
                    RoundedRectangle(cornerRadius: 3)
                        .fill(.tujiTeal)
                        .frame(width: geo.size.width * self.coord.progress)
                        .animation(.spring(duration: 0.5), value: self.coord.progress)
                }
            }
            .frame(height: 6)
        }
        .padding(.horizontal, Space.s6)
        .padding(.top, Space.s1)
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

    private static let abc = ["A", "B", "C", "D", "E"]

    var body: some View {
        ScrollView {
            VStack(spacing: Space.s4) {
                self.bubble
                self.hero
                self.choicesList
            }
            .padding(.horizontal, Space.s6)
            // PR #46: in study mode the tab bar is gone so we can trim the
            // big s24 scroll buffer that previously kept the footer clear.
            .padding(.bottom, self.studyFocus.active ? Space.s4 : Space.s24)
        }
    }

    private var bubble: some View {
        MascotSpeechBubble(pose: self.coord.combo >= 3 ? .cheer : .think, text: "這個是什麼？")
    }

    private var hero: some View {
        ZStack(alignment: .bottomTrailing) {
            GeometryReader { proxy in
                ZStack {
                    Rectangle().fill(.tujiBg)
                    LazyImage(url: self.item.word.imageURL) { state in
                        if let image = state.image {
                            image.resizable()
                                .scaledToFit()
                                .frame(
                                    width: max(0, proxy.size.width - Space.s4),
                                    height: max(0, proxy.size.height - Space.s4)
                                )
                        } else if state.error != nil {
                            Image(systemName: "photo")
                                .foregroundStyle(.tujiInk4)
                        } else {
                            ProgressView().tint(.tujiTeal)
                        }
                    }
                    .pipeline(.shared)
                }
            }
            .frame(height: self.heroHeight)
            .clipped()
            .clipShape(.rect(cornerRadius: Radius.lg))

            PronunciationButton(
                text: self.item.word.word,
                language: self.item.word.wordLanguage,
                audioUrls: self.words.find(id: self.item.word.id)?.audioUrls,
                size: 36
            )
            .padding(Space.s3)
        }
    }

    private var choicesList: some View {
        VStack(spacing: Space.s2) {
            let choices = self.computedChoices
            ForEach(Array(choices.enumerated()), id: \.element) { idx, choice in
                self.optionRow(label: choice, letter: Self.abc[idx])
            }
        }
    }

    private var computedChoices: [String] {
        // Server choices scrubbed of near-synonyms of the answer + topped up;
        // custom (自制圖鑑) cards build the whole set from the local pool.
        // The variant bumps once the word leaves the screen, so its re-test
        // shows a fresh shuffle instead of rewarding position memory.
        studyChoices(
            for: self.item,
            pool: self.words.words,
            variant: self.coord.choicesVariant(for: self.item)
        )
    }

    private func optionRow(label: String, letter: String) -> some View {
        let style = self.optionStyle(for: label)
        return Button {
            self.coord.pick(label)
        } label: {
            HStack(spacing: Space.s3) {
                Text(letter)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(style.letterFg)
                    .frame(width: 24, height: 24)
                    .background(style.letterBg, in: .circle)
                Text(label)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(style.fg)
                Spacer()
                if let icon = style.icon {
                    Image(systemName: icon).foregroundStyle(style.iconColor)
                }
            }
            .padding(.horizontal, Space.s4)
            .padding(.vertical, Space.s3)
            .background(style.bg, in: .rect(cornerRadius: Radius.lg))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.lg)
                    .stroke(style.border, lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
        .disabled(self.coord.phase == .review)
        .opacity(style.opacity)
    }

    private func optionStyle(for label: String) -> OptionStyle {
        guard self.coord.phase == .review, let picked = coord.picked else {
            return OptionStyle.idle
        }
        let isAnswer = label == self.item.word.word
        let isPicked = label == picked
        if isPicked, isAnswer { return .right }
        if isPicked, !isAnswer { return .wrong }
        if isAnswer { return .answer }
        return .dim
    }

    private struct OptionStyle {
        let bg: Color
        let border: Color
        let fg: Color
        let letterFg: Color
        let letterBg: Color
        let icon: String?
        let iconColor: Color
        let opacity: Double

        static let idle = OptionStyle(
            bg: .tujiCard, border: .tujiInk4.opacity(0.25),
            fg: .tujiInk, letterFg: .tujiInk3, letterBg: .tujiTealSoft,
            icon: nil, iconColor: .clear, opacity: 1
        )
        static let right = OptionStyle(
            bg: .tujiGreen.opacity(0.12), border: .tujiGreen,
            fg: .tujiInk, letterFg: .white, letterBg: .tujiGreen,
            icon: "checkmark.circle.fill", iconColor: .tujiGreen, opacity: 1
        )
        static let wrong = OptionStyle(
            bg: .tujiCoral.opacity(0.12), border: .tujiCoral,
            fg: .tujiInk, letterFg: .white, letterBg: .tujiCoral,
            icon: "xmark.circle.fill", iconColor: .tujiCoral, opacity: 1
        )
        static let answer = OptionStyle(
            bg: .tujiGreen.opacity(0.08), border: .tujiGreen.opacity(0.7),
            fg: .tujiInk, letterFg: .white, letterBg: .tujiGreen,
            icon: "arrow.left.circle.fill", iconColor: .tujiGreen, opacity: 1
        )
        static let dim = OptionStyle(
            bg: .tujiCard, border: .tujiInk4.opacity(0.15),
            fg: .tujiInk3, letterFg: .tujiInk4, letterBg: .tujiInk4.opacity(0.15),
            icon: nil, iconColor: .clear, opacity: 0.5
        )
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
                .font(.system(size: 15, weight: .semibold))
            Text(self.label)
                .font(.system(size: 15, weight: .semibold))
        }
        .foregroundStyle(.white)
        .padding(.horizontal, Space.s5)
        .padding(.vertical, Space.s3)
        .background(self.tint, in: .capsule)
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
            case .again: .tujiCoral
            case .hard: .tujiYellow
            case .good: .tujiTeal
            case .easy: .tujiGreen
            }
        case .retestPassed: .tujiGreen
        }
    }
}
