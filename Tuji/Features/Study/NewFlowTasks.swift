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

extension NewFlowCoordinator {
    /// The string the spell stage quizzes: the hiragana reading for JA words
    /// (so the learner judges the kana), else the term form.
    nonisolated static func spellSubject(for item: StudyQueueItem) -> String {
        if let r = item.word.reading, !r.isEmpty { return r }
        return item.word.word
    }

    func spellSubject(for item: StudyQueueItem) -> String {
        Self.spellSubject(for: item)
    }

    /// True when we're quizzing a kana reading distinct from the written term
    /// (JA). Drives the on-device wrong-variant generation and the view's
    /// kanji-reveal + prompt wording. `reading` is a JA-only backend field, so
    /// its presence reliably distinguishes JA-with-kana from EN.
    func spellUsesReading(for item: StudyQueueItem) -> Bool {
        guard let r = item.word.reading, !r.isEmpty else { return false }
        return r != item.word.word
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
    nonisolated static func tileBoard(for item: StudyQueueItem) -> TileBoard {
        let subject = self.spellSubject(for: item)
        var tokenUnits = subject
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
    func tileUnits(for item: StudyQueueItem, attempt: Int) -> [String] {
        let board = Self.tileBoard(for: item)
        var rng = SeededRNG(seed: studyStableHash("\(item.id)#tiles#\(attempt)"))
        var units = board.orderedUnits
        units.shuffle(using: &rng)
        if units.joined() == board.target, units.count >= 2 {
            units.swapAt(0, units.count - 1)
        }
        return units
    }
}
