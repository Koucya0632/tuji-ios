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
    /// Preview gate: the session opens on a scannable list of today's words
    /// (a pre-teach pass) and the queue only starts on 開始學習.
    @State private var started = false

    init(queue: [StudyQueueItem]) {
        self.queue = queue
        self._coord = State(initialValue: NewFlowCoordinator(queue: queue))
    }

    var body: some View {
        VStack(spacing: 0) {
            if self.started {
                self.header
                self.stepContent
            } else {
                self.preview
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.tujiBg)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    // Nothing is lost before the first task or after the last,
                    // so only the mid-session exit needs a confirmation.
                    if !self.started || self.coord.finished {
                        self.dismiss()
                    } else {
                        self.showExitConfirm = true
                    }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.tujiInk2)
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                if !self.coord.finished {
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
            title: "要離開這次學習嗎？",
            message: "完成全部步驟的字會保留，其餘下次重新開始。",
            primary: TujiPromptAction("先離開") { self.dismiss() },
            secondary: TujiPromptAction("繼續學習", role: .cancel) {}
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
        .task { await self.teach.preload(queue: self.queue, words: self.words) }
        .fullScreenCover(item: self.$reportDraft) { draft in
            StudyReportSheet(draft: draft)
        }
    }

    private func cardWord(for id: String) -> CardWord? {
        self.words.find(id: id)
    }

    private func captureReport() {
        guard let task = self.coord.current, !task.item.card.id.hasPrefix("atlas:") else { return }
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
    private var preview: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: Space.s5) {
                    MascotSpeechBubble(
                        pose: .think,
                        text: "先看一眼這些字，準備好就開始"
                    )
                    Text("今天學這 \(self.queue.count) 個字")
                        .font(.tujiH3)
                        .foregroundStyle(.tujiInk)
                    StudyWordGrid(items: self.queue)
                }
                .padding(.horizontal, Space.s6)
                .padding(.top, Space.s4)
                .padding(.bottom, Space.s6)
            }
            BBtn(
                title: "開始學習",
                bg: .tujiTeal,
                fg: .white,
                fullWidth: true,
                icon: "play.fill",
                action: { self.started = true }
            )
            .padding(.horizontal, Space.s6)
            .padding(.bottom, Space.s5)
        }
    }

    private var header: some View {
        VStack(spacing: Space.s3) {
            HStack {
                Text("學新字")
                    .font(.tujiOverline)
                    .tracking(2)
                    .foregroundStyle(.tujiTeal)
                Spacer()
                if !self.coord.finished {
                    Text("完成 \(self.coord.clearedWords) / \(self.coord.queue.count) 字")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.tujiInk3)
                        .contentTransition(.numericText())
                }
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
            // The interleave hides that every word walks the same ladder —
            // the pips make the current word's 認識→選字→拼字 position explicit.
            if let task = self.coord.current {
                NewStagePips(steps: self.coord.stagePlan(for: task.item))
            }
        }
        .padding(.horizontal, Space.s6)
        .padding(.top, Space.s2)
        .padding(.bottom, Space.s4)
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
            NewDoneView(coord: self.coord, queue: self.coord.queue, onFinish: { self.dismiss() })
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
                        .fill(.tujiInk4.opacity(0.3))
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
                        .font(.system(size: 8, weight: .heavy))
                        .foregroundStyle(.white)
                case .active:
                    Circle()
                        .stroke(.tujiTeal, lineWidth: 2)
                        .frame(width: 16, height: 16)
                    Circle()
                        .fill(.tujiTeal)
                        .frame(width: 6, height: 6)
                case .pending:
                    EmptyView()
                }
            }
            Text(self.label(step.kind))
                .font(.system(size: 12, weight: step.state == .active ? .bold : .semibold))
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
        case .done: .tujiTeal
        case .skipped: .tujiTeal.opacity(0.35)
        case .active: .tujiTealSoft
        case .pending: .tujiInk4.opacity(0.25)
        }
    }

    private func labelColor(_ state: NewStageStep.State) -> Color {
        switch state {
        case .done: .tujiInk3
        case .skipped: .tujiInk4
        case .active: .tujiTeal
        case .pending: .tujiInk4
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
