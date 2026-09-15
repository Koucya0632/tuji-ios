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
    /// Leaving, 報錯 and the finish screen — see `StudySession`.
    @State private var shell: StudySessionShell
    @Environment(\.dismiss) private var dismiss
    @Environment(StudyFocus.self) private var studyFocus
    /// Set when the post-session refresh lands. CompleteView's 還有 N 個 CTA
    /// waits for it — before that round-trip the store holds the pre-session
    /// due count.
    @State private var sessionRefreshed = false

    init(queue: [StudyQueueItem]) {
        self.queue = queue
        let coord = ReviewFlowCoordinator(queue: queue)
        self._coord = State(initialValue: coord)
        self._shell = State(initialValue: StudySessionShell(kind: .review, session: coord))
    }

    var body: some View {
        Group {
            if self.coord.finished {
                StudySessionFinish(
                    shell: self.shell,
                    onFinish: { self.dismiss() },
                    onRefreshed: { self.sessionRefreshed = true },
                    summary: {
                        CompleteView(
                            answered: self.coord.answered,
                            masteryByWord: self.coord.writes.masteryByWord,
                            wrongIds: self.coord.retriedIds,
                            unsyncedCount: self.coord.writes.parkedCount,
                            onFinish: { self.dismiss() },
                            onAnotherRound: { await self.startAnotherRound() },
                            refreshed: self.sessionRefreshed
                        )
                    }
                )
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
        .studySessionShell(self.shell)
    }

    /// 再來一輪 from CompleteView: fetch a fresh due queue (via the coordinator's
    /// injected queue provider) and restart the flow with a clean coordinator —
    /// the swap resets `finished`, so the surface flips back to the question view
    /// without re-navigating.
    private func startAnotherRound() async {
        let queue = await self.coord.fetchAnotherRound()
        guard !queue.isEmpty else { return }
        let coord = ReviewFlowCoordinator(queue: queue)
        self.coord = coord
        self.shell.session = coord
    }

    private var flowSurface: some View {
        GeometryReader { geo in
            VStack(spacing: 0) {
                StudySessionNavBar(shell: self.shell)
                self.header
                if let question = self.coord.question {
                    ReviewQuestionView(
                        coord: self.coord,
                        question: question,
                        heroHeight: self.heroHeight(in: geo)
                    )
                } else {
                    Spacer()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            // Keep the MCQ option recolour on pick smooth (previously carried
            // by the footer's ZStack animation).
            .animation(.spring(duration: 0.35), value: self.coord.question?.phase)
            // Ruling an option out does not move `phase`, so the alert frame
            // would otherwise snap in with no motion at all.
            .animation(Motion.ease(Motion.d1), value: self.coord.question?.wrongPicks)
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
                        && !self.shell.confirmingExit && !self.shell.leaving
                },
                set: { _ in }
            )) {
                ReviewRevealSheet(coord: self.coord)
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
    /// For intents only. What is drawn comes from `question`.
    let coord: ReviewFlowCoordinator
    let question: ReviewQuestion
    let heroHeight: CGFloat

    @Environment(StudyFocus.self) private var studyFocus
    @Environment(WordsStore.self) private var words
    @Environment(SettingsStore.self) private var settings
    @Environment(NetworkMonitor.self) private var network
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
                if !self.question.ready {
                    // Nothing of the answer may be drawn yet. 選字's hero is the
                    // answer's own picture, so rendering the default `kind` for
                    // the frame before `prepareQuestion` returns would show the
                    // answer to a question that turns out to be 聽句.
                    self.skeleton
                } else if self.question.kind == .hearSentence,
                          let example = self.question.example,
                          let options = self.question.imageOptions
                {
                    ReviewListenCard(
                        question: self.question,
                        example: example,
                        height: self.heroHeight,
                        onRevealSentence: { self.coord.revealSentence() },
                        onReplay: { slow in
                            Task { await self.coord.replaySentence(slow: slow) }
                        }
                    )
                    ReviewImageChoices(question: self.question, options: options) {
                        self.coord.pickImage($0)
                    }
                    .padding(.horizontal, Space.s4)
                    // The way out for someone who cannot hear right now — no
                    // headphones, a train, company. 聽句 is the only question
                    // in the app that is unanswerable without audio, so it is
                    // the only one that needs this. Drawn under the options
                    // rather than up by the play button: it is the last resort,
                    // and it should read after them, not compete with them.
                    if self.question.canOptOutOfListening {
                        Button("這輪不做聽句題") {
                            self.coord.optOutOfListening()
                        }
                        .font(.tujiLabel)
                        .foregroundStyle(.tujiInk3)
                        .padding(.top, Space.s2)
                    }
                } else {
                    ReviewHeroCard(question: self.question, height: self.heroHeight) {
                        self.coord.toggleHint()
                    }
                    self.choicesList
                        .padding(.horizontal, Space.s4)
                }
            }
            // PR #46: in study mode the tab bar is gone so we can trim the
            // big s24 scroll buffer that previously kept the footer clear.
            .padding(.bottom, self.studyFocus.active ? Space.s3 : Space.s6)
        }
        // Which question this card asks is decided *here*, as it becomes
        // current — not once for the whole session. The network can drop
        // mid-session, and 聽句 without a playable clip degrades to on-device
        // synthesis of a sentence the app cannot correct (ADR-0014). Keyed on
        // the presentation, so a re-test of the same word re-decides (and
        // re-draws its sentence and its distractor).
        .task(id: self.question.presentationId) {
            await self.coord.prepareQuestion(
                pool: self.words.words,
                session: self.session,
                online: self.network.isConnected,
                voice: .preferred(
                    for: self.settings.current,
                    language: self.question.item.word.taggedLanguage
                )
            )
        }
    }

    /// The shape of a question, with none of its content. Deliberately the same
    /// blocks at the same sizes for either kind — a skeleton that already looked
    /// like 聽句 would announce the question before it was decided, which is a
    /// smaller version of the leak it exists to prevent.
    ///
    /// It has to render something: a `body` that resolves to nothing never runs
    /// its `.task`, so an empty branch here would mean the question is never
    /// decided and the skeleton is permanent.
    private var skeleton: some View {
        VStack(spacing: Space.s3) {
            Rectangle()
                .fill(.tujiPaper2)
                .frame(height: self.heroHeight)
            HStack(spacing: Space.s2) {
                ForEach(0..<2, id: \.self) { _ in
                    Rectangle()
                        .fill(.tujiPaper2)
                        .frame(maxWidth: .infinity)
                        .aspectRatio(1, contentMode: .fit)
                }
            }
            .padding(.horizontal, Space.s4)
        }
        .accessibilityHidden(true)
    }

    private var choicesList: some View {
        StudyChoiceList(
            item: self.question.item,
            variant: self.question.variant,
            picked: self.question.picked?.label,
            revealed: !self.question.acceptsAnswer,
            wrongPicks: self.question.wrongPicks
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
