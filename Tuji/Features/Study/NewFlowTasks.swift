// Task model + deterministic variant helpers for the interleaved new-word
// lesson. Split from NewFlowCoordinator (which owns the mutable scheduling
// state): everything here is pure — same inputs, same outputs across SwiftUI
// re-renders and app launches.

import Foundation

enum NewTaskKind: String, Hashable {
    case recognize
    case identify
    case spellTiles = "spell_tiles"
}

struct NewStudyTask: Hashable, Identifiable {
    let item: StudyQueueItem
    let kind: NewTaskKind

    var id: String {
        "\(self.item.id)#\(self.kind.rawValue)"
    }
}

/// The tile puzzle for one word: correct-order units grouped per whitespace
/// token. Token boundaries drive the slot rows (a space is never a tile);
/// correctness compares the assembled picks against the whitespace-stripped
/// `target`, so "cutting board" is solved as cutting+board on two rows.
struct TileBoard: Hashable {
    let tokenUnits: [[String]]

    var orderedUnits: [String] {
        self.tokenUnits.flatMap(\.self)
    }

    var target: String {
        self.orderedUnits.joined()
    }

    var unitCount: Int {
        self.tokenUnits.reduce(0) { $0 + $1.count }
    }
}

/// One entry of a word's stage ladder (認識 → 選字 → 拼字) as shown by the
/// header pips. `skipped` marks a stage removed by the fast path (an 已認識
/// self-rating drops 選字) — visually a dimmed check, not a hole.
struct NewStageStep: Hashable, Identifiable {
    enum State: Hashable {
        case pending, active, done, skipped
    }

    let kind: NewTaskKind
    let state: State

    var id: NewTaskKind {
        self.kind
    }
}

extension SRSRating {
    /// One step harsher — used when quiz mistakes contradict the self-rating.
    var downgraded: SRSRating {
        switch self {
        case .easy: .good
        case .good: .hard
        case .hard, .again: .again
        }
    }
}

/// 拼字題目 — what the spell stage is asking the learner to assemble.
///
/// This was two predicates over `reading`, both documented as "distinguishes JA
/// from EN". They do not: バスマット is Japanese and its 振假名 is itself, so the
/// stage quizzes the 詞形 and the answer is `.term`. The language question and
/// this one agree on most words and part company on exactly the words that make
/// 振假名 subtle — which is why they get separate names.
nonisolated enum SpellSubject: Equatable {
    /// A kana reading distinct from the written term: 排出這個字的讀音. Drives the
    /// on-device wrong-variant generation and the kanji reveal.
    case reading(String)
    /// The term itself: 拼出這個字. Every English word, and Japanese already
    /// written in kana.
    case term(String)

    /// The string being assembled, whichever question is being asked.
    var text: String {
        switch self {
        case let .reading(text), let .term(text): text
        }
    }

    var isReading: Bool {
        if case .reading = self { return true }
        return false
    }
}

/// How a tile board is made. These used to hang off `NewFlowCoordinator` as a
/// `nonisolated static` extension purely to borrow its name — nothing about a
/// tile board needs a coordinator, and `TilesView` had to `typealias` its way
/// back out. A module named after one of its callers does not get found by the
/// next one.
extension TileBoard {
    /// `reading` is a JA-only backend field, so a non-empty one that differs
    /// from the term is a kana reading worth quizzing on its own.
    nonisolated static func spellSubject(for item: StudyQueueItem) -> SpellSubject {
        guard let reading = item.word.reading, !reading.isEmpty else {
            return .term(item.word.word)
        }
        return reading == item.word.word ? .term(reading) : .reading(reading)
    }

    /// Board caps at 10 tiles; longer subjects re-chunk so the pool stays a
    /// recall task instead of a 13-tile hunt.
    nonisolated static let maxTileCount = 10

    /// Small kana that merge into the preceding unit so a yōon like きょ is
    /// one tile. Sokuon っ/ッ stays standalone — it's a full mora.
    private nonisolated static let mergingSmallKana =
        Set("ゃゅょぁぃぅぇぉゎャュョァィゥェォヮ")

    /// Board layout for a word — deterministic per item and independent of
    /// the retry attempt (chunk boundaries must not move between retries;
    /// only the pool shuffle re-seeds).
    nonisolated static func of(_ item: StudyQueueItem) -> TileBoard {
        var tokenUnits = self.spellSubject(for: item).text
            .split(whereSeparator: \.isWhitespace)
            .map { self.baseUnits(for: $0) }
        let total = tokenUnits.reduce(0) { $0 + $1.count }
        if total > self.maxTileCount {
            let chunkLen = Int((Double(total) / Double(self.maxTileCount)).rounded(.up))
            tokenUnits = tokenUnits.map { self.chunked($0, size: chunkLen) }
        }
        return TileBoard(tokenUnits: tokenUnits)
    }

    /// One grapheme per unit, with small kana glued to their base kana.
    private nonisolated static func baseUnits(for token: Substring) -> [String] {
        var units: [String] = []
        for ch in token {
            if self.mergingSmallKana.contains(ch), !units.isEmpty {
                units[units.count - 1].append(ch)
            } else {
                units.append(String(ch))
            }
        }
        return units
    }

    /// Regroup consecutive units into chunks of `size`, never across tokens
    /// (callers chunk per token).
    private nonisolated static func chunked(_ units: [String], size: Int) -> [String] {
        guard size > 1 else { return units }
        var out: [String] = []
        var idx = 0
        while idx < units.count {
            let end = min(idx + size, units.count)
            out.append(units[idx..<end].joined())
            idx = end
        }
        return out
    }

    /// Scrambled tile pool — deterministic per (item, attempt) so re-renders
    /// don't reshuffle mid-task, but a retry gets a new scramble. Never reads
    /// as the answer itself (that would be a free win).
    nonisolated static func units(for item: StudyQueueItem, attempt: Int) -> [String] {
        let board = Self.of(item)
        var rng = SeededRNG(seed: studyStableHash("\(item.id)#tiles#\(attempt)"))
        var units = board.orderedUnits
        units.shuffle(using: &rng)
        if units.joined() == board.target, units.count >= 2 {
            units.swapAt(0, units.count - 1)
        }
        return units
    }
}

/// The spell board as the view should draw it.
///
/// `tilePicked` is one flat `[Int]` shared across every word, indexing a
/// per-item, per-attempt unit list. Handing the view those two raw pieces
/// meant both sides had to subscript one with the other — and they disagreed
/// about what an out-of-range index means: `tilesMatch` bounds-checks and
/// returns `false`, `TilesView.slotBox` did not and would trap. One frame
/// during the `.id(currentPresentationId)` swap between a 7-tile board and a
/// 3-tile board hits both readers at once.
///
/// The view also re-derived the verdict the coordinator had just computed
/// and thrown away. It is stored now, so "did they get it right" is answered
/// once, where the answer is made.
struct SpellBoard: Equatable {
    struct Slot: Equatable {
        /// nil = still empty.
        var unit: String?
    }

    struct Tile: Equatable {
        var unit: String
        var used: Bool
    }

    var slots: [Slot]
    var pool: [Tile]
    /// 拼字題目, spaces intact: what the 正解 line reveals, and which of the
    /// two questions the board is asking. The view used to read the string
    /// here and go back to the coordinator for the question.
    var subject: SpellSubject
    /// How the units group into rows (a multi-word subject spells one row
    /// per word).
    var tokenUnits: [[String]]
    /// nil until the board fills and locks.
    var verdict: Bool?

    var isLocked: Bool {
        self.verdict != nil
    }
}
