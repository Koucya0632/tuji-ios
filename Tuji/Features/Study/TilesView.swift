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

import Nuke
import NukeUI
import SwiftUI

struct TilesView: View {
    let coord: NewFlowCoordinator
    let item: StudyQueueItem

    @Environment(SettingsStore.self) private var settings
    @Environment(WordsStore.self) private var words
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Indices into `units`, in tap order. Index-based so duplicate units
    /// stay distinguishable. Local state — the flow view keys this whole view
    /// by (task, attempt), so a requeued task starts clean.
    @State private var picked: [Int] = []

    private var units: [String] {
        self.coord.tileUnits(for: self.item)
    }

    private var board: TileBoard {
        NewFlowCoordinator.tileBoard(for: self.item)
    }

    /// The original subject (spaces intact) — the 正解 reveal shows this.
    private var subject: String {
        self.coord.spellSubject(for: self.item)
    }

    private var assembled: String {
        self.picked.map { self.units[$0] }.joined()
    }

    private var boardFull: Bool {
        self.picked.count == self.units.count
    }

    private var isCorrect: Bool {
        self.assembled == self.board.target
    }

    /// Result colours apply once the board is full (the coordinator locks at
    /// that moment via tilesAnswer).
    private var showResult: Bool {
        self.boardFull && self.coord.tiLocked
    }

    var body: some View {
        VStack(spacing: Space.s4) {
            self.bubble
            self.card
            Spacer(minLength: 0)
            self.slotsRow
            self.tilePool
        }
        .padding(.horizontal, Space.s6)
        .padding(.bottom, Space.s5)
        .onChange(of: self.boardFull) { _, full in
            guard full else { return }
            self.coord.tilesAnswer(correct: self.isCorrect)
        }
    }

    @ViewBuilder
    private var bubble: some View {
        if self.showResult {
            MascotSpeechBubble(
                pose: self.isCorrect ? .cheer : .think,
                text: self.isCorrect ? "拼對了！" : "差一點，看看正解",
                tone: self.isCorrect ? .success : .error,
                systemImage: self.isCorrect ? "checkmark.circle.fill" : "xmark.circle.fill"
            )
            // A little hop when the word comes out right — the reward moment
            // of the production task deserves more than a colour swap.
            .scaleEffect(self.isCorrect && !self.reduceMotion ? 1.05 : 1.0)
            .animation(
                self.reduceMotion ? nil : .spring(duration: 0.35, bounce: 0.55),
                value: self.showResult
            )
        } else {
            MascotSpeechBubble(
                pose: self.coord.combo >= 3 ? .cheer : .think,
                text: self.coord.spellUsesReading(for: self.item)
                    ? "排出這個字的讀音"
                    : "拼出這個字"
            )
        }
    }

    private var card: some View {
        VStack(spacing: Space.s3) {
            self.hero
            HStack {
                if self.settings.current.showZh {
                    Text(self.item.word.chinese)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.tujiInk)
                }
                Spacer()
                PronunciationButton(
                    text: self.item.word.word,
                    audioUrls: self.words.find(id: self.item.word.id)?.audioUrls,
                    size: 36
                )
            }
            .padding(.horizontal, Space.s4)
            .padding(.bottom, Space.s3)
        }
        .background(.tujiCard, in: .rect(cornerRadius: Radius.xl))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.xl)
                .stroke(.tujiInk4.opacity(0.15), lineWidth: 1)
        )
    }

    private var hero: some View {
        ZStack {
            Rectangle().fill(.tujiBg)
            LazyImage(url: self.item.word.imageURL) { state in
                if let image = state.image {
                    image.resizable()
                        .aspectRatio(contentMode: .fit)
                        .padding(Space.s2)
                } else if state.error != nil {
                    Image(systemName: "photo")
                        .font(.system(size: 28))
                        .foregroundStyle(.tujiInk4)
                } else {
                    ProgressView().tint(.tujiTeal)
                }
            }
            .pipeline(.shared)
        }
        .frame(height: 168)
        .clipped()
        .clipShape(.rect(topLeadingRadius: Radius.xl, topTrailingRadius: Radius.xl))
    }

    /// Answer slots — one box per unit, one row per token (the visual stand-in
    /// for the space, which is never a tile); tapping a filled box takes that
    /// unit back out (before the board locks).
    private var slotsRow: some View {
        VStack(spacing: Space.s2) {
            ForEach(0..<self.board.tokenUnits.count, id: \.self) { row in
                HStack(spacing: Space.s1) {
                    ForEach(self.slotRange(ofRow: row), id: \.self) { slot in
                        self.slotBox(at: slot)
                    }
                }
            }
        }
        // After the wrong-freeze, reveal the correct spelling under the red
        // board so the peek sheet isn't the only place carrying the answer.
        .overlay(alignment: .bottom) {
            if self.showResult, !self.isCorrect {
                Text("正解 \(self.subject)")
                    .font(.tujiCaption)
                    .foregroundStyle(.tujiInk3)
                    .offset(y: 22)
            }
        }
        .padding(.bottom, Space.s2)
    }

    /// Flat slot indices covered by a token row (picked stays one flat list).
    private func slotRange(ofRow row: Int) -> Range<Int> {
        let counts = self.board.tokenUnits.map(\.count)
        let start = counts.prefix(row).reduce(0, +)
        return start..<(start + counts[row])
    }

    @ViewBuilder
    private func slotBox(at slot: Int) -> some View {
        let unit: String? = slot < self.picked.count ? self.units[self.picked[slot]] : nil
        Button {
            guard !self.coord.tiLocked, slot < self.picked.count else { return }
            self.picked.remove(at: slot)
        } label: {
            Text(unit ?? " ")
                .font(.system(size: 22, weight: .heavy, design: .monospaced))
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .foregroundStyle(self.slotFg)
                .frame(maxWidth: 52)
                .frame(height: 46)
                .background(self.slotBg(filled: unit != nil), in: .rect(cornerRadius: Radius.md))
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.md)
                        .stroke(self.slotBorder(filled: unit != nil), lineWidth: 1.5)
                )
        }
        .buttonStyle(.plain)
        .disabled(self.coord.tiLocked || unit == nil)
    }

    private var slotFg: Color {
        guard self.showResult else { return .tujiInk }
        return self.isCorrect ? .tujiGreen : .tujiCoral
    }

    private func slotBg(filled: Bool) -> Color {
        if self.showResult {
            return (self.isCorrect ? Color.tujiGreen : .tujiCoral).opacity(0.12)
        }
        return filled ? .tujiTealSoft : .tujiCard
    }

    private func slotBorder(filled: Bool) -> Color {
        if self.showResult {
            return self.isCorrect ? .tujiGreen : .tujiCoral
        }
        return filled ? .tujiTeal.opacity(0.5) : .tujiInk4.opacity(0.3)
    }

    /// The scrambled tiles. A used tile stays in place but dims, so the board
    /// doesn't reflow under the user's finger. Multi-unit tiles (chunked long
    /// words, merged yōon kana) get fewer, wider columns.
    private var tilePool: some View {
        let hasWideUnits = self.units.contains { $0.count > 1 }
        return LazyVGrid(
            columns: Array(
                repeating: GridItem(.flexible(), spacing: Space.s2),
                count: hasWideUnits
                    ? max(3, min(5, self.units.count))
                    : max(4, min(6, self.units.count))
            ),
            spacing: Space.s2
        ) {
            ForEach(0..<self.units.count, id: \.self) { idx in
                self.tile(at: idx)
            }
        }
    }

    @ViewBuilder
    private func tile(at idx: Int) -> some View {
        let used = self.picked.contains(idx)
        Button {
            guard !self.coord.tiLocked, !used else { return }
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            self.picked.append(idx)
        } label: {
            Text(self.units[idx])
                .font(.system(size: 22, weight: .heavy, design: .monospaced))
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .foregroundStyle(used ? .tujiInk4 : .tujiInk)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(used ? Color.tujiBg : .tujiCard, in: .rect(cornerRadius: Radius.md))
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.md)
                        .stroke(used ? Color.tujiInk4.opacity(0.15) : .tujiInk4.opacity(0.35), lineWidth: 1.5)
                )
                .opacity(used ? 0.45 : 1)
        }
        .buttonStyle(.plain)
        .disabled(self.coord.tiLocked || used)
    }
}
