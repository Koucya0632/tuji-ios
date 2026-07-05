// Task model + deterministic variant helpers for the interleaved new-word
// lesson. Split from NewFlowCoordinator (which owns the mutable scheduling
// state): everything here is pure — same inputs, same outputs across SwiftUI
// re-renders and app launches.

import Foundation

enum NewTaskKind: String, Hashable {
    case recognize
    case identify
    case spellJudge = "spell"
    case spellTiles = "spell_tiles"
}

struct NewStudyTask: Hashable, Identifiable {
    let item: StudyQueueItem
    let kind: NewTaskKind

    var id: String {
        "\(self.item.id)#\(self.kind.rawValue)"
    }
}

enum JudgeAnswer: Hashable {
    case yes, no
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
    /// 拼字塊 (arrange scrambled letters — production) when the subject is a
    /// short single token; longer or multi-word subjects keep the judge task,
    /// where a 13-tile board would be busywork rather than recall.
    static func spellStageKind(for item: StudyQueueItem) -> NewTaskKind {
        let subject = self.spellSubject(for: item)
        if subject.count >= 2, subject.count <= 8, !subject.contains(" ") {
            return .spellTiles
        }
        return .spellJudge
    }

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

    /// Correct-or-wrong is decided per item *and* per attempt from a stable
    /// hash — the old global attempt parity alternated 對/錯/對/錯 across
    /// consecutive cards, so the whole stage could be passed without reading.
    /// Deterministic for a given (item, attempt) because the view re-evaluates
    /// this on every render.
    func spellShown(for item: StudyQueueItem, attempt: Int) -> String {
        let subject = Self.spellSubject(for: item)
        let showCorrect = studyStableHash("\(item.id)#spell#\(attempt)") % 2 == 0
        if showCorrect {
            return subject
        }
        if self.spellUsesReading(for: item) {
            return Self.fallbackMisspelling(subject)
        }
        // Rotate through the backend's wrong spellings across attempts; fall
        // back to a tweaked version if nothing's attached.
        let wrongs = (item.spellingChoices ?? []).filter { $0 != subject }
        if !wrongs.isEmpty {
            return wrongs[attempt % wrongs.count]
        }
        return Self.fallbackMisspelling(subject)
    }

    private static func fallbackMisspelling(_ word: String) -> String {
        // Simple cosmetic fallback: swap last two letters when both are
        // letters. Good enough when backend forgot to attach options.
        var chars = Array(word)
        guard chars.count >= 2 else { return word + "?" }
        chars.swapAt(chars.count - 1, chars.count - 2)
        return String(chars)
    }

    /// Scrambled tiles for the subject — deterministic per (item, attempt) so
    /// re-renders don't reshuffle mid-task, but a retry gets a new scramble.
    /// Never equals the subject itself (that would be a free answer).
    func tileLetters(for item: StudyQueueItem, attempt: Int) -> [String] {
        let subject = Self.spellSubject(for: item)
        var rng = SeededRNG(seed: studyStableHash("\(item.id)#tiles#\(attempt)"))
        var letters = subject.map(String.init)
        letters.shuffle(using: &rng)
        if letters.joined() == subject, letters.count >= 2 {
            letters.swapAt(0, letters.count - 1)
        }
        return letters
    }
}
