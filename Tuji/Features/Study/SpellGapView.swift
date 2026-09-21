// 挖空拼字 — the 拼字 board for English. Shows the image + 中文 and the word
// itself with a few chunks cut out of it; the user fills the holes from a
// shuffled pool of look-alikes (pres ___ vative, from ur / ar / or / er / ir).
//
// It replaced the tile board for English because re-assembling every letter
// quizzes "do you remember each character", while English spelling actually
// goes wrong in a handful of places — the r-controlled vowels, the vowel teams,
// the suffix families, the doubled consonants. SpellGaps cuts exactly those.
//
// The gesture is the tile board's: tap a pool entry to fill the leftmost empty
// slot, tap a filled slot to take it back, auto-check when the last one lands.
// One coordinator path drives both (see NewFlowCoordinator.pickSpell).

import SwiftUI

struct SpellGapView: View {
    let coord: NewFlowCoordinator
    let item: StudyQueueItem

    private var board: SpellGapBoard? {
        self.coord.gapBoard
    }

    var body: some View {
        // No board means the coordinator has moved off this task — one frame
        // during a task swap. Draw nothing rather than index into a stale pair.
        if let board = self.board {
            self.content(board)
        }
    }

    private func content(_ board: SpellGapBoard) -> some View {
        VStack(spacing: Space.s3) {
            self.bubble(board)
            SpellPromptCard(word: self.item.word, showsGloss: false)
            Spacer(minLength: 0)
            self.wordLine(board)
            self.pool(board)
        }
        .padding(.horizontal, Space.s4)
        .padding(.bottom, Space.s4)
    }

    /// Same rule as the tile board: the cat is for the wrong answer only, and
    /// the instruction stays as a line rather than as a character.
    @ViewBuilder
    private func bubble(_ board: SpellGapBoard) -> some View {
        if board.verdict == false {
            MascotSpeechBubble(pose: .peek, text: "差一點，看看正解")
        } else if board.verdict == nil {
            Text("補上缺少的部分")
                .font(.tujiLabel)
                .tracking(0.5)
                .foregroundStyle(.tujiInk3)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// The word with its holes. One line, scaled down rather than wrapped, so a
    /// long headword ("air conditioner") stays a single readable shape.
    private func wordLine(_ board: SpellGapBoard) -> some View {
        HStack(spacing: 0) {
            ForEach(Array(board.segments.enumerated()), id: \.offset) { index, segment in
                Text(segment)
                    .font(.tujiHeadword(30))
                    .foregroundStyle(.tujiInk)
                if index < board.slots.count {
                    self.slotBox(board, at: index)
                }
            }
        }
        .lineLimit(1)
        .minimumScaleFactor(0.5)
        .frame(maxWidth: .infinity)
        // After the wrong-freeze, reveal the whole spelling under the red board
        // so the peek sheet isn't the only place carrying the answer.
        .overlay(alignment: .bottom) {
            if board.verdict == false {
                Text("正解 \(board.term)")
                    .font(.tujiLabel)
                    .foregroundStyle(.tujiInk3)
                    .offset(y: 26)
            }
        }
        .padding(.bottom, Space.s3)
    }

    /// A hole. Sized to the pool's widest option rather than to its own answer:
    /// a box that grows with the answer would tell you how many letters go in
    /// it, which is half the question on a 3-vs-4-letter family.
    private func slotBox(_ board: SpellGapBoard, at index: Int) -> some View {
        let slot = board.slots[index]
        let verdict = board.verdict
        let active = board.activeSlot == index
        return Button {
            self.coord.unpickSpell(atSlot: index)
        } label: {
            Text(slot.filled ?? " ")
                .font(.tujiHeadword(30))
                .foregroundStyle(self.slotFg(slot, verdict: verdict))
                .frame(minWidth: self.slotWidth(board))
                .overlay(alignment: .bottom) {
                    Rectangle()
                        .fill(self.ruleColor(slot, verdict: verdict, active: active))
                        .frame(height: active ? 3 : 2)
                        .offset(y: 4)
                }
        }
        .buttonStyle(.plain)
        .disabled(verdict != nil || slot.filled == nil)
        .padding(.horizontal, Space.s1)
    }

    /// Roughly one headword character per letter of the widest option, floored
    /// so a single-letter hole is still an obvious target.
    private func slotWidth(_ board: SpellGapBoard) -> CGFloat {
        max(34, CGFloat(board.widestOption.count) * 19)
    }

    private func slotFg(_ slot: SpellGapBoard.Slot, verdict: Bool?) -> Color {
        guard verdict != nil else { return .tujiInk }
        return slot.isCorrect ? .tujiAccumulation : .tujiAlert
    }

    /// Per-slot marking once the answer is out: a wrong board should say which
    /// chunk missed, not just that the word came out wrong.
    private func ruleColor(_ slot: SpellGapBoard.Slot, verdict: Bool?, active: Bool) -> Color {
        if verdict != nil {
            return slot.isCorrect ? .tujiAccumulation : .tujiAlert
        }
        if active { return .tujiAccumulation }
        return slot.filled == nil ? .tujiPaper3 : .tujiAccumulation.opacity(0.5)
    }

    /// The shuffled chunks. A used option stays in place but dims, so the grid
    /// doesn't reflow under the user's finger — same reason as the tile pool.
    private func pool(_ board: SpellGapBoard) -> some View {
        LazyVGrid(
            columns: Array(
                repeating: GridItem(.flexible(), spacing: Space.s2),
                count: min(3, board.pool.count)
            ),
            spacing: Space.s2
        ) {
            ForEach(Array(board.pool.enumerated()), id: \.offset) { index, option in
                self.optionTile(option, at: index, locked: board.isLocked)
            }
        }
    }

    private func optionTile(_ option: SpellBoard.Tile, at index: Int, locked: Bool) -> some View {
        let used = option.used
        return Button {
            guard !locked, !used else { return }
            self.coord.pickSpell(index)
        } label: {
            Text(option.unit)
                .font(.tujiHeadword(22))
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .foregroundStyle(used ? .tujiInk3 : .tujiInk)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(.tujiPaper)
                .overlay(
                    Rectangle()
                        .stroke(used ? Color.tujiRule.opacity(0.15) : .tujiRule.opacity(0.35), lineWidth: 1.5)
                )
                .opacity(used ? 0.45 : 1)
        }
        .buttonStyle(.plain)
        .disabled(locked || used)
    }
}
