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
    @State private var showExitConfirm = false

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
        }
        .alert("離開練習？", isPresented: self.$showExitConfirm) {
            Button("繼續練習", role: .cancel) {}
            Button("離開", role: .destructive) { self.dismiss() }
        } message: {
            Text("目前進度會丟失")
        }
        .sheet(item: Binding(
            get: { self.coord.peek.map { PeekIdent(word: $0) } },
            set: { self.coord.peek = $0?.word }
        )) { wrap in
            if let card = self.cardWord(for: wrap.word.id) {
                WordPeekSheet(word: card, onSeeMore: { self.coord.peek = nil })
            }
        }
        .onAppear { self.studyFocus.enter() }
        .onDisappear { self.studyFocus.exit() }
    }

    private func cardWord(for id: String) -> CardWord? {
        self.words.find(id: id)
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
