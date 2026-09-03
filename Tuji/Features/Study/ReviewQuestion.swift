// One presentation of one card: what it asks, what the user has done to it,
// and what that adds up to.
//
// It was 32 stored properties on `ReviewFlowCoordinator`, and the coordinator's
// `advance()` was a 16-assignment reset of them — three of which any test had
// ever asserted. Adding a question kind meant adding state and remembering to
// clear it in a list nothing checked, which is how 聽句's six fields came to sit
// beside 複習's cursor without either side knowing where the seam was.
//
// So the reset is a construction: `advance()` builds the next `ReviewQuestion`
// and every field is back at its start value because the value is new. There is
// no list to forget.
//
// **A value type with no beats, locks, audio or writes in it** — the shape
// `StudyLadder` already has. The coordinator keeps everything that outlives one
// card (the queue cursor, the requeue set, the session's 聽句 opt-out, the
// primed haptics, `AnswerBeat`, the writer) and everything with a latency in it:
// this decides, the coordinator performs. That split is what lets the whole
// answering path be exercised synchronously, with no `awaitReveal` and no clock
// to poll.

import Foundation

/// What resolving an answer asks the session to do next.
enum ReviewResolution: Hashable {
    /// A correct re-test: flash and move on. No SRS write — the first
    /// attempt's 重來 already rescheduled the word.
    case flashRetestPassed
    /// Fast, correct, unambiguous: apply this rating without asking.
    case autoRated(SRSRating)
    /// Put the question to the user.
    case reveal(ReviewRevealMode)
}

/// What one tap on an option did.
enum ReviewTap: Hashable {
    /// Guard refused it — wrong phase, or an option already ruled out.
    case ignored
    /// 看圖選字: marked and taken out of play, question still open.
    case ruledOut
    /// The pick that landed.
    case resolved(ReviewResolution)
}

struct ReviewQuestion {
    let item: StudyQueueItem
    /// A re-test of a word missed earlier this session. Re-tests never write
    /// SRS and never requeue again, which is why so many rules read it.
    let isRetest: Bool

    // MARK: - What is being asked

    /// Decided when the card becomes current, not at session start — the
    /// network can drop mid-session and take 聽句's eligibility with it
    /// (ADR-0014).
    private(set) var kind: ReviewQuestionKind = .pickWord
    /// The sentence being asked about, when `kind == .hearSentence`.
    private(set) var example: StudyExample?
    /// The two pictures, when `kind == .hearSentence`.
    private(set) var imageOptions: [ImageChoiceOption]?
    /// Whether the question has been decided.
    ///
    /// The view must draw a skeleton until it has. `kind` defaults to
    /// `.pickWord`, and 選字's hero *is the answer's own picture* — so rendering
    /// the default for the one frame before the decision lands would show the
    /// answer to a question that turns out to be 聽句. Defaulting the other way
    /// does not work either: `.hearSentence` has no sentence to draw yet. The
    /// honest third state is "not decided".
    private(set) var ready: Bool = false

    // MARK: - Answering

    private(set) var phase: ReviewPhase = .answer
    private(set) var picked: String?
    /// Options ruled out on this presentation. 看圖選字 marks a wrong pick and
    /// leaves the question open instead of ending it, so the user finds the
    /// word themselves. Only the pick that lands resolves, and it is graded as
    /// a miss — the rating table, the requeue and the write are untouched.
    private(set) var wrongPicks: Set<String> = []
    /// The user asked to see the gloss. Sticky — flipping back does not un-see
    /// it — and it makes the item take the wrong-answer rating table either
    /// way (ADR-0007).
    private(set) var hinted: Bool = false
    /// Which face the card is showing right now. Distinct from `hinted`: this
    /// one goes back and forth, that one only ever turns on.
    private(set) var hintFaceUp: Bool = false
    private(set) var wasCorrect: Bool = false
    private(set) var suggested: SRSRating = .good
    private(set) var rated: SRSRating?

    // MARK: - The clock

    /// 聽句 starts it when the audio *ends*; everything else at construction.
    private(set) var startedAt: Date
    /// The clock has not started yet. Until it does an answer cannot be timed.
    private(set) var awaitingAudio: Bool = false
    /// How long the answer took, measured **once**, when it landed.
    ///
    /// It used to be spelled twice — `resolve` computed it against
    /// `awaitingAudio` and refused to time an answer given before the clip
    /// ended, while `applyRating` recomputed it unconditionally 138 lines
    /// later. So the *suggestion* said nothing was measured and the row written
    /// to SRS claimed a duration that included the download, the clip, the
    /// 600 ms reveal beat and however long the user spent choosing among three
    /// rating buttons. One reading, taken at the only moment it means anything.
    private(set) var measuredElapsed: TimeInterval?

    // MARK: - 聽句

    /// The eye was pressed and the sentence is legible. One-way within the
    /// presentation, like `hinted` — which it also sets, because reading the
    /// sentence is reading the answer.
    private(set) var sentenceRevealed: Bool = false
    /// Replays before answering. Deliberately does **not** reset the clock:
    /// with the download and the clip length already excluded, replay time
    /// points the right way — needing three listens *is* 困難.
    private(set) var replayCount: Int = 0
    /// The clip was missing/unreachable (so this was on-device synthesis), or
    /// nothing came out at all.
    private(set) var audioFailed: Bool = false
    /// Whether the sentence is playing right now, for the play button.
    private(set) var isPlayingSentence: Bool = false
    /// This presentation is the one the user turned listening off on.
    private(set) var convertedFromListening: Bool = false

    // MARK: - Progress bookkeeping

    /// Whether the progress bar has already counted this word.
    ///
    /// The count happens at two different moments — immediately for a re-test
    /// or an auto-rated answer, and only after the rating for anything that
    /// goes to the sheet — so the guard is what keeps one rule from becoming
    /// two counters.
    private(set) var counted: Bool = false

    init(item: StudyQueueItem, isRetest: Bool, now: Date = .now) {
        self.item = item
        self.isRetest = isRetest
        self.startedAt = now
    }

    // MARK: - Presenting

    /// Record what this card turned out to be asking.
    ///
    /// `awaitsAudio` is separate from `kind == .hearSentence` because the card
    /// is drawn and answerable while the sentence plays — only the clock waits.
    ///
    /// **A sentence is what makes it a listening question**, so asking for one
    /// without an example lands on 選字 — the same fallback every other
    /// ineligible card takes. The caller's own eligibility arithmetic already
    /// rules the combination out; keeping the invariant here as well is what
    /// lets everything below read `kind` alone instead of `kind` and a nil
    /// check the next reader has to know about.
    mutating func present(
        kind: ReviewQuestionKind,
        example: StudyExample?,
        imageOptions: [ImageChoiceOption]?,
        awaitsAudio: Bool
    ) {
        if kind == .hearSentence, let example {
            self.kind = .hearSentence
            self.example = example
            self.imageOptions = imageOptions
            self.awaitingAudio = awaitsAudio
        } else {
            self.kind = .pickWord
            self.example = nil
            self.imageOptions = nil
        }
        self.ready = true
    }

    // MARK: - 聽句 controls

    /// A play has begun. Returns false when this question has no sentence, so
    /// the caller does not start audio for a 選字 card.
    mutating func playbackBegan() -> Bool {
        guard self.kind == .hearSentence else { return false }
        self.isPlayingSentence = true
        return true
    }

    /// A play has ended. Only the first opens the clock — a replay must not
    /// reset it, or the button becomes a way to buy time, and the time a replay
    /// costs is exactly the signal that this word was hard.
    mutating func playbackEnded(_ outcome: ListeningPlayback, isReplay: Bool, now: Date = .now) {
        self.isPlayingSentence = false
        if outcome != .finished { self.audioFailed = true }
        if !isReplay, self.awaitingAudio {
            self.awaitingAudio = false
            self.startedAt = now
        }
    }

    /// 慢讀 counts as a replay, because it is one: reaching for it says the
    /// sentence did not land at speed. Returns false when there is nothing to
    /// replay.
    mutating func willReplay() -> Bool {
        guard self.kind == .hearSentence, self.example != nil else { return false }
        self.replayCount += 1
        return true
    }

    /// Lift the blur. Same cost as 求救提示's flip and for a stronger reason:
    /// the sentence spells the answer out, so from here this is a reading
    /// question, not a listening one (ADR-0014).
    mutating func revealSentence() {
        guard self.phase == .answer, self.kind == .hearSentence else { return }
        self.sentenceRevealed = true
        self.hinted = true
    }

    /// 這輪不做聽句題, applied to the card in front of the user.
    ///
    /// Someone presses this *because* they cannot answer the one they are
    /// looking at, so leaving it up would be asking a question they just said
    /// they cannot hear. The clock restarts, because a different question
    /// starts now. Nothing is marked `hinted`: no answer was revealed.
    ///
    /// `replayCount` and `audioFailed` need no reset — the payload reads them
    /// only when `kind == .hearSentence`, so they stop being sent the moment
    /// the kind changes.
    mutating func optOutOfListening(now: Date = .now) -> Bool {
        guard self.phase == .answer, self.kind == .hearSentence else { return false }
        self.convertedFromListening = true
        self.kind = .pickWord
        self.example = nil
        self.imageOptions = nil
        self.sentenceRevealed = false
        self.isPlayingSentence = false
        self.awaitingAudio = false
        self.startedAt = now
        return true
    }

    // MARK: - 求救提示

    /// Flip the image over to read the gloss, and back. Only while the item is
    /// still unanswered: the reveal sheet rests at `.fraction(0.4)` with
    /// background interaction enabled, so the hero stays tappable underneath it
    /// and an answered item would otherwise still turn.
    mutating func toggleHint() {
        guard self.phase == .answer, self.kind == .pickWord else { return }
        self.hintFaceUp.toggle()
        if self.hintFaceUp { self.hinted = true }
    }

    /// Whether the 8-second 「點一下圖片」 nudge still has anything to teach.
    ///
    /// Never in 聽句. That delay compensates for an affordance drawn nowhere —
    /// 選字's hint is a tap on a picture with nothing to say so — and 聽句's eye
    /// is on screen from the first frame.
    var canNudge: Bool {
        self.phase == .answer && !self.hinted && !self.isRetest && self.kind == .pickWord
    }

    // MARK: - Answering

    /// One of the two pictures in 聽句. Compared by id, not by label: two
    /// catalogue words can print the same string, they cannot share an id.
    mutating func pickImage(_ option: ImageChoiceOption, now: Date = .now) -> ReviewTap {
        guard self.kind == .hearSentence else { return .ignored }
        return self.resolve(
            picked: option.word,
            correct: option.id == self.item.word.id,
            now: now
        )
    }

    /// 看圖選字. A wrong option is marked and taken out of play while the
    /// question stays open — the user keeps choosing until they find the word.
    ///
    /// What it hands `resolve` is **whether they got it first try**, not
    /// whether this tap was right: everything downstream reads `wasCorrect` and
    /// none of it counts taps, so the rating table, the requeue and the payload
    /// stay exactly the wrong-answer path they have always been.
    ///
    /// 聽句 is not on this path. Ruling out one of *two* pictures is the same
    /// act as answering, so `pickImage` resolves on the first tap — the same
    /// 50% that keeps it off the auto-rate path (ADR-0014).
    mutating func pick(_ choice: String, now: Date = .now) -> ReviewTap {
        guard self.phase == .answer else { return .ignored }
        let ok = choice == self.item.word.word
        if !ok, self.kind == .pickWord {
            // The row is disabled once it is in the set; this keeps a repeat
            // from being caught by the haptic alone.
            guard self.wrongPicks.insert(choice).inserted else { return .ignored }
            return .ruledOut
        }
        return self.resolve(picked: choice, correct: ok && self.wrongPicks.isEmpty, now: now)
    }

    private mutating func resolve(picked choice: String, correct ok: Bool, now: Date) -> ReviewTap {
        guard self.phase == .answer else { return .ignored }
        // Answering before the sentence finished leaves nothing timed — the
        // clock had not started. It may be genuine (the word was recognised
        // mid-sentence) or a rush, and the two are indistinguishable, so the
        // suggestion falls back to correctness rather than claiming a speed
        // that was never measured.
        self.measuredElapsed = self.awaitingAudio ? nil : now.timeIntervalSince(self.startedAt)
        self.suggested = Self.suggestion(
            correct: ok,
            elapsed: self.measuredElapsed,
            mastery: self.item.mastery,
            hinted: self.hinted
        )
        self.picked = choice
        self.wasCorrect = ok
        self.phase = .review

        if self.isRetest {
            // Practice only, never a second SRS write.
            return .resolved(ok ? .flashRetestPassed : .reveal(.continueOnly))
        }
        if ok, self.suggested != .hard, self.kind == .pickWord {
            // The suggestion is unambiguous — apply it and keep the session
            // moving instead of raising a sheet to confirm it.
            //
            // 聽句 is excluded by that very precondition, not by an exception:
            // its answer is one of *two* pictures, so a fast correct answer is
            // one coin flip and "unambiguous" is not true of it (ADR-0014).
            return .resolved(.autoRated(self.suggested))
        }
        // Wrong, or correct-but-slow: the user's own judgment carries signal.
        return .resolved(.reveal(.rate))
    }

    /// Record the rating this presentation was given, whichever path applied
    /// it. Returns false when one has already landed.
    mutating func applyRating(_ rating: SRSRating) -> Bool {
        guard self.rated == nil else { return false }
        self.rated = rating
        return true
    }

    /// Rating buttons in the reveal sheet. Wrong answers offer only 重來/困難
    /// (困難 = misclick escape hatch) — anything higher would let a missed word
    /// skip its relearn. Correct-but-slow answers pick among the three positive
    /// ratings.
    ///
    /// A hinted answer takes the wrong-answer table even when it was right: the
    /// user told us they could not retrieve the word, so 穩定/熟練 are not
    /// theirs to claim. Only the *suggestion* still tracks correctness.
    var availableRatings: [SRSRating] {
        guard self.wasCorrect, !self.hinted else { return [.again, .hard] }
        return [.hard, .good, .easy]
    }

    /// What has been chosen so far, for 報錯: the pick that ended the question,
    /// or the options ruled out while it is still open. `picked` is only set by
    /// the pick that lands, so without this a report filed mid-question would
    /// throw away everything the user had already tried.
    var reportedSelection: String? {
        self.picked ?? (self.wrongPicks.isEmpty
            ? nil
            : self.wrongPicks.sorted().joined(separator: " / "))
    }

    // MARK: - Progress

    /// Whether nothing will ask this word again, so the progress bar may count
    /// it.
    ///
    /// One rule for what used to be three `passedCount += 1` sites under three
    /// different conditions. A re-test settles the moment it resolves (it never
    /// requeues and is never rated); anything else settles when a rating lands,
    /// and only if it was right — a wrong one goes back on the tail.
    var settled: Bool {
        guard self.phase == .review else { return false }
        if self.isRetest { return true }
        guard self.rated != nil else { return false }
        return self.wasCorrect
    }

    mutating func markCounted() {
        self.counted = true
    }

    // MARK: - The payload

    /// The SRS row for this presentation.
    ///
    /// `listeningOptedOut` is the session's, not the question's, so it arrives
    /// as an argument: it rides on **every** activity, because a session that
    /// turned 聽句 off answers the rest of its cards as 選字, and rows that
    /// cannot be told apart from a session that never met a listening question
    /// are what makes an aggregate accuracy lie.
    func payload(rating: SRSRating, listeningOptedOut: Bool) -> StudyAnswerPayload {
        let listening = self.kind == .hearSentence
        return StudyAnswerPayload(
            cardId: self.item.card.id,
            rating: rating,
            responseMs: self.measuredElapsed.map { Int($0 * 1000) },
            activity: self.kind.asActivity,
            hinted: self.hinted,
            // Only 聽句 has these, and sending them as nil elsewhere keeps a
            // 選字 row's metadata honestly empty rather than claiming zero
            // replays of audio that was never played.
            replayCount: listening ? self.replayCount : nil,
            audioFailed: listening ? self.audioFailed : nil,
            listeningOptedOut: listeningOptedOut ? true : nil,
            convertedFromListening: self.convertedFromListening ? true : nil
        )
    }

    // MARK: - The suggestion

    /// Computed once per answer. Fast correct answers auto-apply this; the
    /// sheet highlights it as 建議 otherwise. Mastery caps the top end: a
    /// 2-second hit on a barely-known word is normal recall, not 熟練 — only
    /// well-established words (score ≥ 50) earn the long-interval jump.
    ///
    /// A hinted item is capped at 困難 regardless of speed. That cap is also
    /// what switches off the auto-rate path, which requires a suggestion other
    /// than 困難 — see ADR-0007.
    ///
    /// `elapsed` is nil when nothing was timed — 聽句 answered before its
    /// sentence finished. A correct-but-untimed answer suggests 穩定: 熟練 is
    /// the one rating that rests entirely on the speed signal, and claiming it
    /// without one would be inventing the evidence.
    static func suggestion(
        correct: Bool,
        elapsed: TimeInterval?,
        mastery: Int?,
        hinted: Bool = false
    )
        -> SRSRating
    {
        if !correct { return .again }
        if hinted { return .hard }
        guard let elapsed else { return .good }
        switch elapsed {
        case ..<3: return (mastery ?? 0) >= 50 ? .easy : .good
        case ..<7: return .good
        default: return .hard
        }
    }
}
