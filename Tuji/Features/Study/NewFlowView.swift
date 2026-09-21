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
    /// Leaving, 報錯 and the finish screen — see `StudySession`.
    @State private var shell: StudySessionShell
    @State private var teach = NewFlowTeachLoader()
    @Environment(\.dismiss) private var dismiss
    @Environment(WordsStore.self) private var words
    /// Preview gate: the session opens on a scannable list of today's words
    /// (a pre-teach pass) and the queue only starts on 開始學習.
    @State private var started = false

    init(queue: [StudyQueueItem]) {
        self.queue = queue
        let coord = NewFlowCoordinator(queue: queue)
        self._coord = State(initialValue: coord)
        self._shell = State(initialValue: StudySessionShell(kind: .new, session: coord))
    }

    var body: some View {
        VStack(spacing: 0) {
            StudySessionNavBar(
                shell: self.shell,
                // Nothing is lost before the first task or after the last, so
                // only the mid-session exit needs a confirmation.
                confirmsExit: self.started && !self.coord.finished,
                offersReport: !self.coord.finished
            )
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
        .task {
            await self.teach.preload(queue: self.queue, words: self.words)
        }
        // Outside the peek sheet, so the sheet inherits its word-detail rule.
        .studySessionShell(self.shell)
    }

    private func cardWord(for id: String) -> CardWord? {
        self.words.find(id: id)
    }

    /// Pre-session scan of today's words: reading the grid before the first
    /// card is itself a teach pass, and the explicit 開始學習 makes the
    /// lesson feel like a chosen unit instead of an ambush.
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
                case .spell:
                    // Which 拼字 board this word takes is SpellForm's call, and
                    // the ladder gated the stage on the same predicate — so a
                    // task that got scheduled always has one of the two.
                    switch SpellForm.of(task.item) {
                    case .gaps:
                        SpellGapView(coord: self.coord, item: task.item)
                    case .tiles, nil:
                        TilesView(coord: self.coord, item: task.item)
                    }
                }
            }
            // Keyed per (task, attempt): a requeued task returns as a fresh
            // view — local state like assembled tiles resets, and the options
            // reshuffle takes visual effect.
            .id(self.coord.currentPresentationId)
        } else if self.coord.finished {
            // Learning new words writes mastery + creates user_cards +
            // study_logs (the deferred recognize POSTs fired as each word
            // cleared 拼字). The finish reloads — not just invalidates — every
            // store the home surfaces read: Today stays mounted under this push,
            // so its .task won't re-run on pop, and an invalidated-but-unreloaded
            // store leaves 今日目標 0/10 and the streak flame at 0.
            StudySessionFinish(
                shell: self.shell,
                onFinish: { self.dismiss() },
                summary: {
                    NewDoneView(coord: self.coord, queue: self.coord.queue, onFinish: { self.dismiss() })
                }
            )
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
        case .spell: "拼字"
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
