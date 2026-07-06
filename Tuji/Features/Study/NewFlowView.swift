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
    @Environment(\.dismiss) private var dismiss
    @Environment(WordsStore.self) private var words
    @Environment(StudyFocus.self) private var studyFocus
    @Environment(SettingsStore.self) private var settings
    @State private var showExitConfirm = false
    @State private var reportDraft: StudyReportDraft?

    init(queue: [StudyQueueItem]) {
        self.queue = queue
        self._coord = State(initialValue: NewFlowCoordinator(queue: queue))
    }

    var body: some View {
        VStack(spacing: 0) {
            self.header
            self.stepContent
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.tujiBg)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    if self.coord.finished {
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
            message: "完成全部三步的字會保留，其餘下次重新開始。",
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
                    RecognizeView(coord: self.coord, item: task.item)
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

/// Wrapper to make the optional peek word Identifiable for .sheet(item:).
private struct PeekIdent: Identifiable {
    let word: StudyQueueWord
    var id: String {
        self.word.id
    }
}
