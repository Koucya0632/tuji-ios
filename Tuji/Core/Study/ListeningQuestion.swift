// Which sentence 聽句 asks, and which cards get asked at all.
//
// Two pure decisions, kept out of `ReviewFlowCoordinator` because both are
// total functions over data the tests can hand them, and neither needs a beat,
// a lock, or a network.
//
// See CONTEXT.md (聽句) and docs/adr/0014-listening-changes-the-rating-preconditions.md.

import Foundation

enum ListeningQuestion {
    /// Above this mastery the word gets the harder (B1) sentence, below it the
    /// simpler (A2) one.
    ///
    /// Deliberately the same 50 `computeSuggestion` already uses to decide
    /// whether a two-second answer earns 熟練. That number is answering the
    /// same question — is this word actually established, or merely recalled —
    /// and a second threshold would be a second constant nobody could explain.
    static let masteryTier = 50

    /// CEFR level of the simpler / harder sentence of an authored pair. Every
    /// published word has exactly one of each (`lib/main-word-example-pairs.ts`,
    /// enforced on every production migrate), so these are the whole ladder.
    static let simpleLevel = "A2"
    static let complexLevel = "B1"

    /// The sentence to ask about, or nil when the card carries none.
    ///
    /// `presentation` is how many times this word has already been *left* —
    /// the same counter that reshuffles MCQ options. Presentation 0 takes the
    /// tier its mastery earns; a re-test (presentation ≥ 1) takes the other
    /// sentence, because replaying the recording the user just failed is not
    /// practice. With more presentations than sentences it clamps rather than
    /// wrapping: a third look at a two-sentence word has nothing new to offer
    /// and pretending otherwise would just alternate.
    static func example(
        for item: StudyQueueItem,
        mastery: Int?,
        presentation: Int
    )
        -> StudyExample?
    {
        let examples = item.examples ?? []
        guard !examples.isEmpty else { return nil }
        let wanted = (mastery ?? 0) >= self.masteryTier ? self.complexLevel : self.simpleLevel
        // Stable partition, not a sort: within a tier the authored order is the
        // only order there is, and `sorted(by:)` in Swift is not guaranteed
        // stable, so it could reorder a tier between two identical calls.
        let preferred = examples.filter { $0.cefrLevel == wanted }
        let rest = examples.filter { $0.cefrLevel != wanted }
        let ordered = preferred + rest
        return ordered[min(max(presentation, 0), ordered.count - 1)]
    }

    /// One in this many eligible cards is asked as 聽句.
    ///
    /// A constant rather than a dice roll: random clusters, and three listening
    /// questions in a row turns a review into a listening test the user never
    /// asked for — each one costs an extra tap (the reveal sheet is mandatory,
    /// ADR-0014) plus the clip. A constant is also the only version this
    /// coordinator's tests can assert; a roll would need a seed injected purely
    /// so the assertion could exist.
    static let everyN = 4

    /// Whether this word's turn falls on a 聽句 slot. Hashed rather than
    /// counted so the answer does not move when the queue is re-ordered, and
    /// `studyStableHash` rather than `hashValue` so it does not move between
    /// launches either.
    static func fallsOnSlot(wordId: String) -> Bool {
        studyStableHash(wordId) % UInt64(self.everyN) == 0
    }

    /// The question to ask, given what the card can support and what the last
    /// one was.
    ///
    /// - `canHear`: this presentation has a sentence *and* a clip that will
    ///   actually play right now. Offline with nothing cached is a no — the
    ///   fallback inside `SpeechService` is on-device synthesis, and a
    ///   Japanese sentence read by a reading the app cannot correct is not a
    ///   worse question, it is an unanswerable one (ADR-0014).
    /// - `previous`: the kind the *previous presentation* used. Two 聽句 in a
    ///   row is the cluster `everyN` exists to avoid, so the second demotes.
    /// - `alreadyHeard`: this word has already been asked as 聽句 this session,
    ///   i.e. this is its re-test. A re-test keeps its question — it is
    ///   practice on what was missed, and it writes no SRS — so the spacing
    ///   rule does not apply to it.
    static func kind(
        wordId: String,
        canHear: Bool,
        previous: ReviewQuestionKind?,
        alreadyHeard: Bool
    )
        -> ReviewQuestionKind
    {
        guard canHear else { return .pickWord }
        if alreadyHeard { return .hearSentence }
        if previous == .hearSentence { return .pickWord }
        return self.fallsOnSlot(wordId: wordId) ? .hearSentence : .pickWord
    }
}
