// NewFlow root (§III.P). Owns the NewFlowCoordinator, renders the
// header + progress, then dispatches to RecognizeView / IdentifyView /
// SpellView / NewDoneView based on coordinator.step. Wrong answers
// in steps 2 & 3 surface a WordPeekSheet via coordinator.peek.

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
                    if self.coord.step == .done {
                        self.dismiss()
                    } else {
                        self.showExitConfirm = true
                    }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 16, weight: .heavy))
                        .foregroundStyle(.tujiInk2)
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                if self.coord.step != .done {
                    Menu {
                        Button("報錯", systemImage: "exclamationmark.bubble") {
                            self.captureReport()
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.system(size: 17, weight: .heavy))
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
            message: "目前進度會丟失，下次會重新開始。",
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
        let item: StudyQueueItem?
        let phase: String
        let answer: String?
        let shown: String?
        switch self.coord.step {
        case .recognize:
            item = self.coord.recognizeItem
            phase = "recognize"
            answer = self.coord.recRating?.rawValue
            shown = nil
        case .identify:
            item = self.coord.identifyItem
            phase = "identify"
            answer = self.coord.idPicked
            shown = nil
        case .spell:
            item = self.coord.spellItem
            phase = "spell"
            answer = self.coord.spJudge == .yes ? "yes" : self.coord.spJudge == .no ? "no" : nil
            shown = item.map { self.coord.spellShown(for: $0) }
        case .done:
            return
        }
        guard let item else { return }
        self.reportDraft = StudyReportDraft(
            item: item,
            mode: "new",
            phase: phase,
            selectedAnswer: answer,
            uiLang: self.settings.current.uiLang,
            displayedSpelling: shown
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
                Text(self.headerCount)
                    .font(.system(size: 13, weight: .heavy))
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
        .padding(.top, Space.s2)
        .padding(.bottom, Space.s4)
    }

    private var headerCount: String {
        switch self.coord.step {
        case .recognize: "\(self.coord.recIdx + 1) / \(self.coord.queue.count)"
        case .identify: "剩 \(self.coord.identifyRemaining)"
        case .spell: "剩 \(self.coord.spellRemaining)"
        case .done: ""
        }
    }

    @ViewBuilder
    private var stepContent: some View {
        switch self.coord.step {
        case .recognize:
            if let item = coord.recognizeItem {
                RecognizeView(coord: self.coord, item: item)
            }
        case .identify:
            if let item = coord.identifyItem {
                IdentifyView(coord: self.coord, item: item)
            }
        case .spell:
            if let item = coord.spellItem {
                SpellView(coord: self.coord, item: item)
            }
        case .done:
            NewDoneView(queue: self.coord.queue, onFinish: { self.dismiss() })
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
