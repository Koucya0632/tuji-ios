// NewFlow root (§III.P). Owns the NewFlowCoordinator, renders the
// header + progress, then dispatches on the current interleaved task's
// kind to RecognizeView / IdentifyView / TilesView, and to
// NewDoneView once the queue drains. Wrong answers surface a
// WordPeekSheet via coordinator.peek.

import OSLog
import Observation
import SwiftUI

struct NewFlowView: View {
    let queue: [StudyQueueItem]
    @State private var coord: NewFlowCoordinator
    @State private var teach = NewFlowTeachLoader()
    @Environment(\.dismiss) private var dismiss
    @Environment(WordsStore.self) private var words
    @Environment(StudyFocus.self) private var studyFocus
    @Environment(SettingsStore.self) private var settings
    @State private var showExitConfirm = false
    @State private var reportDraft: StudyReportDraft?
    @State private var showCustomCardNotice = false
    /// Preview gate: the session opens on a scannable list of today's words
    /// (a pre-teach pass) and the queue only starts on 開始學習.
    @State private var started = false

    init(queue: [StudyQueueItem]) {
        self.queue = queue
        self._coord = State(initialValue: NewFlowCoordinator(queue: queue))
    }

    var body: some View {
        VStack(spacing: 0) {
            self.navBar
            if self.started {
                self.header
                self.stepContent
            } else {
                self.preview
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.tujiPaper)
        .navigationBarBackButtonHidden(true)
        // Drawn in-content: on iOS 26 a system toolbar item is a floating glass
        // circle, and two white discs are the platform talking over the lesson.
        .toolbar(.hidden, for: .navigationBar)
        .tujiPrompt(
            isPresented: self.$showExitConfirm,
            style: .confirmation,
            title: "要離開這次學習嗎？",
            message: "完成全部步驟的字會保留，其餘下次重新開始。",
            // Cancel first, then leave. An answer given moments before ✕ still
            // had a beat in flight; without this it resolved — and posted its
            // SRS write — after the screen was gone.
            primary: TujiPromptAction("先離開") {
                self.coord.cancelPendingBeats()
                self.dismiss()
            },
            secondary: TujiPromptAction("繼續學習", role: .cancel) {}
        )
        .tujiPrompt(
            isPresented: self.$showCustomCardNotice,
            style: .confirmation,
            title: "自制卡片暫不支援報錯",
            message: "報錯僅適用於官方單字內容。自制卡片如有問題，可以到自制圖鑑刪除重拍，或透過「我的」頁的意見收集告訴我們。",
            primary: TujiPromptAction("知道了") {}
        )
        .sheet(
            item: Binding(
                get: { self.coord.peek.map { PeekIdent(word: $0) } },
                set: { self.coord.peek = $0?.word }
            ),
            // onDismiss is the single advance entry point: tapping 下一題 sets
            // peek = nil (dismiss) and swipe-down dismisses too — both land
            // here, so the queue advances exactly once either way.
            onDismiss: { self.coord.advanceFromPeek() }
        ) { wrap in
            if let card = self.cardWord(for: wrap.word.id) {
                WordPeekSheet(
                    word: card,
                    ctaTitle: "下一題",
                    showDetailOnExpand: true,
                    onSeeMore: { self.coord.peek = nil }
                )
            }
        }
        .onAppear { self.studyFocus.enter() }
        .onDisappear { self.studyFocus.exit() }
        .task {
            AnalyticsService.shared.track(.studyStart, category: "new")
            await self.teach.preload(queue: self.queue, words: self.words)
        }
        .fullScreenCover(item: self.$reportDraft) { draft in
            StudyReportSheet(draft: draft)
        }
    }

    private func cardWord(for id: String) -> CardWord? {
        self.words.find(id: id)
    }

    private func captureReport() {
        guard let task = self.coord.current else { return }
        // Custom cards have no cards-table row, so /api/study/reports
        // can't accept them — explain instead of silently dropping the tap.
        guard !task.item.card.id.hasPrefix("atlas:") else {
            self.showCustomCardNotice = true
            return
        }
        let answer: String? = switch task.kind {
        case .recognize: self.coord.recRating?.rawValue
        case .identify: self.coord.idPicked
        case .spellTiles: nil
        }
        self.reportDraft = StudyReportDraft(
            item: task.item,
            mode: "new",
            phase: task.kind.rawValue,
            selectedAnswer: answer,
            uiLang: self.settings.current.uiLang,
            displayedSpelling: nil
        )
    }

    /// Pre-session scan of today's words: reading the grid before the first
    /// card is itself a teach pass, and the explicit 開始學習 makes the
    /// lesson feel like a chosen unit instead of an ambush.
    private var navBar: some View {
        TujiNavBar(
            leading: .close,
            onLeading: {
                // Nothing is lost before the first task or after the last,
                // so only the mid-session exit needs a confirmation.
                if !self.started || self.coord.finished {
                    self.dismiss()
                } else {
                    self.showExitConfirm = true
                }
            }
        ) {
            if !self.coord.finished {
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
        }
    }

    private var preview: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: Space.s4) {
                    // 開始 is one of C.11's four mascot moments, and the pose it
                    // asks for is wave — the cat greeting the session, not
                    // thinking about it.
                    MascotSpeechBubble(pose: .wave, text: "先看一眼這些字，準備好就開始")
                        .padding(.horizontal, Space.s4)
                    // Left, at the page margin, like every other screen title —
                    // it was centred, which is the one place in the app where a
                    // heading floated free of the vertical line everything else
                    // aligns to.
                    Text("今天學這 \(self.queue.count) 個字")
                        .font(.tujiH1)
                        .foregroundStyle(.tujiInk)
                        .padding(.horizontal, Space.s4)
                    StudyWordGrid(items: self.queue)
                }
                .padding(.top, Space.s3)
                .padding(.bottom, Space.s4)
            }
            // A 24pt fade above the pinned button, so the grid runs out rather
            // than being sliced off mid-row by an opaque bar.
            .overlay(alignment: .bottom) {
                LinearGradient(
                    colors: [.tujiPaper.opacity(0), .tujiPaper],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: Space.s4)
                .allowsHitTesting(false)
            }
            BBtn(
                title: "開始學習",
                bg: .tujiBrandPrimary,
                fg: .tujiInk,
                fullWidth: true,
                action: { self.started = true }
            )
            .padding(.horizontal, Space.s4)
            .padding(.bottom, Space.s4)
        }
    }

    private var header: some View {
        VStack(spacing: Space.s2) {
            HStack {
                Text("學新字")
                    .font(.tujiLabel)
                    .tracking(0.5)
                    .foregroundStyle(.tujiInk3)
                Spacer()
                if !self.coord.finished {
                    Text("完成 \(self.coord.clearedWords) / \(self.coord.queue.count) 字")
                        .font(.tujiMono)
                        .foregroundStyle(.tujiInk2)
                        .contentTransition(.numericText())
                }
            }
            .padding(.horizontal, Space.s4)

            TujiProgressBar(progress: self.coord.progress)
            // The interleave hides that every word walks the same ladder —
            // the pips make the current word's 認識→選字→拼字 position explicit.
            if let task = self.coord.current {
                NewStagePips(steps: self.coord.stagePlan(for: task.item))
                    .padding(.horizontal, Space.s4)
            }
        }
        .padding(.bottom, Space.s3)
    }

    @ViewBuilder
    private var stepContent: some View {
        if let task = self.coord.current {
            Group {
                switch task.kind {
                case .recognize:
                    RecognizeView(
                        coord: self.coord,
                        item: task.item,
                        detail: self.teach.details[task.item.word.id]
                    )
                case .identify:
                    IdentifyView(coord: self.coord, item: task.item)
                case .spellTiles:
                    TilesView(coord: self.coord, item: task.item)
                }
            }
            // Keyed per (task, attempt): a requeued task returns as a fresh
            // view — local state like assembled tiles resets, and the options
            // reshuffle takes visual effect.
            .id(self.coord.currentPresentationId)
        } else if self.coord.finished {
            self.finishedSurface
                // Learning new words writes mastery + creates user_cards +
                // study_logs (the deferred recognize POSTs fired as each word
                // cleared 拼字). Reload — not just invalidate — every store the
                // home surfaces read: Today stays mounted under this push, so
                // its .task won't re-run on pop, and an invalidated-but-unreloaded
                // store leaves 今日目標 0/10 and the streak flame at 0.
                .refreshesFinishedSession(draining: self.coord.writes)
        }
    }

    /// Which celebration a finished session shows. A streak milestone can be
    /// crossed by a 學新字 write just as easily as by a 複習 one — the server
    /// attaches it to whichever answer crosses the threshold. This branch used
    /// to be missing entirely, so those milestones were shown nowhere.
    @ViewBuilder
    private var finishedSurface: some View {
        if let milestone = coord.writes.milestone {
            MilestoneView(milestone: milestone, onFinish: { self.dismiss() })
                .onAppear { AnalyticsService.shared.track(.studyComplete, category: "new") }
        } else {
            NewDoneView(coord: self.coord, queue: self.coord.queue, onFinish: { self.dismiss() })
                .onAppear { AnalyticsService.shared.track(.studyComplete, category: "new") }
        }
    }
}

/// The current word's stage ladder: labeled dots for 認識/選字/拼字 with
/// connecting ticks. Done = filled check, active = ringed dot, skipped
/// (fast path) = dimmed check, pending = hollow.
private struct NewStagePips: View {
    let steps: [NewStageStep]

    var body: some View {
        HStack(spacing: Space.s2) {
            ForEach(Array(self.steps.enumerated()), id: \.element.kind) { idx, step in
                if idx > 0 {
                    RoundedRectangle(cornerRadius: 1)
                        .fill(.tujiPaper2.opacity(0.3))
                        .frame(width: 14, height: 2)
                }
                self.pip(step)
            }
        }
        .frame(maxWidth: .infinity)
        .animation(.easeInOut(duration: 0.2), value: self.steps)
    }

    private func pip(_ step: NewStageStep) -> some View {
        HStack(spacing: 4) {
            ZStack {
                Circle()
                    .fill(self.dotFill(step.state))
                    .frame(width: 16, height: 16)
                switch step.state {
                case .done, .skipped:
                    Image(systemName: "checkmark")
                        .font(.tujiIcon(8, weight: .heavy))
                        .foregroundStyle(.white)
                case .active:
                    Circle()
                        .stroke(.tujiCurrent, lineWidth: 2)
                        .frame(width: 16, height: 16)
                    Circle()
                        .fill(.tujiCurrent)
                        .frame(width: 6, height: 6)
                case .pending:
                    EmptyView()
                }
            }
            Text(self.label(step.kind))
                .font(.tujiLabel)
                .foregroundStyle(self.labelColor(step.state))
        }
    }

    private func label(_ kind: NewTaskKind) -> LocalizedStringKey {
        switch kind {
        case .recognize: "認識"
        case .identify: "選字"
        case .spellTiles: "拼字"
        }
    }

    private func dotFill(_ state: NewStageStep.State) -> Color {
        switch state {
        case .done: .tujiAccumulation
        case .skipped: .tujiAccumulation.opacity(0.35)
        case .active: .tujiCurrent.opacity(0.18)
        case .pending: .tujiPaper3
        }
    }

    private func labelColor(_ state: NewStageStep.State) -> Color {
        switch state {
        case .done: .tujiInk3
        case .skipped: .tujiInk3
        case .active: .tujiInk
        case .pending: .tujiPaper3
        }
    }
}

/// Wrapper to make the optional peek word Identifiable for .sheet(item:).
private struct PeekIdent: Identifiable {
    let word: StudyQueueWord
    var id: String {
        self.word.id
    }
}
