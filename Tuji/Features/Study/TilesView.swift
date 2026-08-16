// 拼字塊 — the production step of NewFlow. Shows the image + 中文 (never the
// word) and a scrambled tile per unit; the user taps tiles into slots to
// spell the word from recall. Auto-checks when every slot is filled: correct
// advances (and commits the word's SRS write upstream), wrong freezes the
// board red and surfaces the WordPeek sheet — the retry comes back later with
// a fresh scramble (coordinator bumps the attempt on advanceFromPeek).
//
// Every word takes this task: the TileBoard splits the subject per whitespace
// token (one slot row each — spaces are never tiles) and re-chunks units so
// long subjects stay within a 10-tile board. Single-unit subjects skip the
// spell stage entirely (see NewFlowCoordinator.initialSchedule).

import SwiftUI

struct TilesView: View {
    let coord: NewFlowCoordinator
    let item: StudyQueueItem

    @Environment(SettingsStore.self) private var settings
    @Environment(WordsStore.self) private var words
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// One value from the coordinator, already resolved.
    ///
    /// This view used to hold six derived properties over `tilePicked` and
    /// `tileUnits(for:)` — including the verdict, which the coordinator had
    /// already computed and discarded. Two readers of the same index pair, and
    /// they disagreed about bounds: the coordinator's was checked, this one's
    /// was a trap.
    private var board: SpellBoard? {
        self.coord.spellBoard
    }

    var body: some View {
        // No board means the coordinator has moved off this task — one frame
        // during a task swap. Draw nothing rather than index into a stale pair.
        if let board = self.board {
            self.content(board)
        }
    }

    private func content(_ board: SpellBoard) -> some View {
        VStack(spacing: Space.s3) {
            self.bubble(board)
            self.card
            Spacer(minLength: 0)
            self.slotsRow(board)
            self.tilePool(board)
        }
        .padding(.horizontal, Space.s4)
        .padding(.bottom, Space.s4)
    }

    /// The cat appears here for exactly one reason: the answer was wrong
    /// (C.11's 答錯後). It used to be on screen the whole time — combo-driven
    /// pose while typing, then a cheering hop and a green ✓ when the word came
    /// out right. Getting a word right is the expected outcome of a spelling
    /// task, and celebrating the expected is what turns study into a slot
    /// machine; the filled slots already say it landed.
    ///
    /// The instruction is not decoration — 拼出這個字 and 排出這個字的讀音 are
    /// different tasks — so it stays, as a line rather than as a character.
    @ViewBuilder
    private func bubble(_ board: SpellBoard) -> some View {
        if board.verdict == false {
            MascotSpeechBubble(pose: .peek, text: "差一點，看看正解")
        } else if board.verdict == nil {
            Text(
                board.subject.isReading
                    ? LocalizedStringKey("排出這個字的讀音")
                    : LocalizedStringKey("拼出這個字")
            )
            .font(.tujiLabel)
            .tracking(0.5)
            .foregroundStyle(.tujiInk3)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var card: some View {
        VStack(spacing: Space.s3) {
            self.hero
            HStack {
                if self.settings.current.showZh {
                    Text(self.item.word.chinese)
                        .font(.tujiBodySm(.strong))
                        .foregroundStyle(.tujiInk)
                }
                Spacer()
                PronunciationButton(
                    text: self.item.word.word,
                    language: self.item.word.taggedLanguage,
                    audioUrls: self.words.find(id: self.item.word.id)?.audioUrls,
                    size: 36
                )
            }
            .padding(.horizontal, Space.s3)
            .padding(.bottom, Space.s3)
        }
        .background(.tujiPaper, in: .rect(cornerRadius: Radius.r0))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.r0)
                .stroke(.tujiRule.opacity(0.15), lineWidth: 1)
        )
    }

    private var hero: some View {
        ZStack {
            Rectangle().fill(.tujiPaper)
            // This screen used to hard-code `.fit` with no blend mode at all,
            // so a dictionary cut-out kept the white rectangle every other
            // screen multiplies away — the one place the 紙與墨 fix never
            // reached.
            WordPicture(
                url: self.item.word.imageURL,
                kind: self.item.word.imageKind,
                inset: Space.s2,
                framing: .whole,
                glyphSize: 28
            )
        }
        .frame(height: 168)
        .clipped()
        .clipShape(.rect(topLeadingRadius: Radius.r0, topTrailingRadius: Radius.r0))
    }

    /// Answer slots — one box per unit, one row per token (the visual stand-in
    /// for the space, which is never a tile); tapping a filled box takes that
    /// unit back out (before the board locks).
    private func slotsRow(_ board: SpellBoard) -> some View {
        VStack(spacing: Space.s2) {
            ForEach(0..<board.tokenUnits.count, id: \.self) { row in
                HStack(spacing: Space.s1) {
                    ForEach(self.slotRange(ofRow: row, in: board), id: \.self) { slot in
                        self.slotBox(board.slots[slot], at: slot, verdict: board.verdict)
                    }
                }
            }
        }
        // After the wrong-freeze, reveal the correct spelling under the red
        // board so the peek sheet isn't the only place carrying the answer.
        .overlay(alignment: .bottom) {
            if board.verdict == false {
                Text("正解 \(board.subject.text)")
                    .font(.tujiLabel)
                    .foregroundStyle(.tujiInk3)
                    .offset(y: 22)
            }
        }
        .padding(.bottom, Space.s2)
    }

    /// Flat slot indices covered by a token row (slots stay one flat list).
    private func slotRange(ofRow row: Int, in board: SpellBoard) -> Range<Int> {
        let counts = board.tokenUnits.map(\.count)
        let start = counts.prefix(row).reduce(0, +)
        return start..<(start + counts[row])
    }

    private func slotBox(_ slot: SpellBoard.Slot, at index: Int, verdict: Bool?) -> some View {
        Button {
            self.coord.unpickTile(atSlot: index)
        } label: {
            Text(slot.unit ?? " ")
                .font(.tujiHeadword(22))
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .foregroundStyle(self.slotFg(verdict))
                .frame(maxWidth: 52)
                .frame(height: 46)
                .background(self.slotBg(filled: slot.unit != nil, verdict: verdict))
                .overlay(
                    Rectangle()
                        .stroke(self.slotBorder(filled: slot.unit != nil, verdict: verdict), lineWidth: 1.5)
                )
        }
        .buttonStyle(.plain)
        .disabled(verdict != nil || slot.unit == nil)
    }

    private func slotFg(_ verdict: Bool?) -> Color {
        guard let verdict else { return .tujiInk }
        return verdict ? .tujiAccumulation : .tujiAlert
    }

    private func slotBg(filled: Bool, verdict: Bool?) -> Color {
        if let verdict {
            return (verdict ? Color.tujiAccumulation : .tujiAlert).opacity(0.12)
        }
        return filled ? .tujiAccumulationSoft : .tujiPaper
    }

    private func slotBorder(filled: Bool, verdict: Bool?) -> Color {
        if let verdict {
            return verdict ? .tujiAccumulation : .tujiAlert
        }
        return filled ? .tujiAccumulation.opacity(0.5) : .tujiPaper3
    }

    /// The scrambled tiles. A used tile stays in place but dims, so the board
    /// doesn't reflow under the user's finger. Multi-unit tiles (chunked long
    /// words, merged yōon kana) get fewer, wider columns.
    private func tilePool(_ board: SpellBoard) -> some View {
        let hasWideUnits = board.pool.contains { $0.unit.count > 1 }
        return LazyVGrid(
            columns: Array(
                repeating: GridItem(.flexible(), spacing: Space.s2),
                count: hasWideUnits
                    ? max(3, min(5, board.pool.count))
                    : max(4, min(6, board.pool.count))
            ),
            spacing: Space.s2
        ) {
            ForEach(Array(board.pool.enumerated()), id: \.offset) { index, tile in
                self.tile(tile, at: index, locked: board.isLocked)
            }
        }
    }

    private func tile(_ tile: SpellBoard.Tile, at index: Int, locked: Bool) -> some View {
        let used = tile.used
        return Button {
            guard !locked, !used else { return }
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            self.coord.pickTile(index)
        } label: {
            Text(tile.unit)
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
