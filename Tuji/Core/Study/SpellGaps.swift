// 挖空拼字 — the English production step of NewFlow.
//
// The word is shown almost whole; a few confusable chunks are cut out of it
// and offered back as one shuffled pool. It replaces the from-scratch tile
// board for English because re-assembling every letter quizzes "do you
// remember each character", while English spelling actually goes wrong in a
// handful of places: the r-controlled vowels (er/ar/or/ur/ir), the vowel teams
// (ai/ay/ei/ey), the suffix families (-tion/-sion, -able/-ible, -ary/-ery) and
// the doubled consonants. Cutting exactly those out puts the attention where
// the mistakes are, and a wrong answer shows the learner *which* chunk they
// got wrong.
//
// Japanese keeps the tile board: its 拼字 stage asks for a kana reading, which
// has no orthographic confusables to cut. See SpellForm.
//
// Placement is pure and `nonisolated`: it needs no actor, and keeping it that
// way means the rules can be exercised from anywhere. Only the pool *order*
// reaches for the seeded RNG — `studyStableHash` is main-actor under the
// module's default isolation — so that part lives apart in
// `options(for:attempt:)`. Same split, and for the same reason, as
// TileBoard.of / TileBoard.units.

import Foundation

nonisolated struct SpellGaps: Equatable {
    /// One cut-out chunk, in the order it appears in the term.
    struct Gap: Equatable {
        let answer: String
        /// Offsets into the term's `Character` view — what the placement rules
        /// are stated in, and what the tests assert on.
        let range: Range<Int>
    }

    /// The whole word, whitespace intact.
    let term: String
    /// The visible text around the gaps: `segments.count == gaps.count + 1`,
    /// interleaved segment/gap/segment/…  Re-joining them rebuilds `term`.
    let segments: [String]
    let gaps: [Gap]
    /// Every answer plus distractors, in canonical order. The *displayed*
    /// order is `options(for:attempt:)`, which shuffles this.
    let options: [String]

    var answers: [String] {
        self.gaps.map(\.answer)
    }
}

// MARK: - The confusable table

extension SpellGaps {
    /// Vowel teams and suffix families — the errors learners actually make, so
    /// they outrank everything else when choosing what to cut.
    private nonisolated static let vowelFamilies: [[String]] = [
        ["tion", "sion", "cian"],
        ["cial", "tial", "sial"],
        ["ence", "ance"],
        ["able", "ible"],
        ["ough", "augh"],
        ["ture", "sure"],
        ["ary", "ery", "ory"],
        ["ous", "ious", "eous"],
        ["ent", "ant"],
        ["ette", "et"],
        ["igh", "ie"],
        ["ai", "ay", "ei", "ey", "ea"],
        ["ee", "ea", "ie", "ei"],
        ["oo", "ou", "ue", "ew"],
        ["ow", "ou", "au", "aw"],
        ["oi", "oy", "oe"],
        ["er", "ar", "or", "ur", "ir"],
        ["le", "el", "al", "il"],
        ["ate", "ite", "ete"],
        ["ive", "ife", "ave"],
        ["age", "idge"]
    ]

    /// Multi-letter consonant ambiguities, including the doubles.
    ///
    /// Every member here is two letters or more on purpose. Allowing a *single*
    /// consonant to be cut produces questions like `bana[n]a` (n/nn) and
    /// `cho[c]olate` (c/ck/k/que) — measured against the corpus, and both are
    /// worthless: the answer is obvious and the word reads as mangled.
    private nonisolated static let consonantFamilies: [[String]] = [
        ["tch", "ch", "sh"],
        ["sh", "ch", "tch"],
        ["dge", "ge"],
        ["ck", "k", "que"],
        ["ph", "f", "gh"],
        ["ce", "se", "ze"],
        ["qu", "kw"],
        ["ll", "l"], ["ss", "s"], ["tt", "t"], ["pp", "p"], ["rr", "r"],
        ["mm", "m"], ["nn", "n"], ["ff", "f"], ["cc", "c"], ["dd", "d"],
        ["gg", "g"], ["zz", "z"]
    ]

    private nonisolated static let vowels = Set("aeiou")

    /// Same-length filler when a family is too small to fill the pool. Never a
    /// correct answer — the caller drops anything already in the pool.
    private nonisolated static let genericChunks: [Int: [String]] = [
        1: ["a", "e", "i", "o", "u"],
        2: ["er", "ar", "or", "ur", "ir", "ee", "ea", "ai", "oo", "ou", "le", "el", "ck", "ll", "ss"],
        3: ["ary", "ery", "ory", "ent", "ant", "ous", "ate", "ive", "age", "ice"],
        4: ["tion", "sion", "able", "ible", "ence", "ance", "ture", "ough"]
    ]

    /// How many chunks a word of this length is worth cutting. The actual count
    /// can come out lower — a word only has so many confusable places.
    private nonisolated static func targetGapCount(letters: Int) -> Int {
        switch letters {
        case ...5: 1
        case ...9: 2
        default: 3
        }
    }

    /// Never blank away more than this share of the word, or it stops being a
    /// gap-fill and becomes the tile board with extra steps.
    private nonisolated static let maxBlankedShare = 0.55

    /// Distractors on top of the answers: 1 gap → 5 options, 2 → 6, 3 → 7.
    private nonisolated static let distractorCount = 4
    private nonisolated static let maxOptions = 8
}

// MARK: - Placement

extension SpellGaps {
    private nonisolated struct Candidate {
        let range: Range<Int>
        let answer: String
        let family: [String]
        let tier: Int
        let rank: Int

        var length: Int {
            self.range.count
        }
    }

    /// Build the gaps for a term, or nil when it cannot carry this question
    /// (an all-caps acronym, no vowel, fewer than three letters).
    nonisolated static func of(term: String) -> SpellGaps? {
        let chars = Array(term)
        let letters = chars.count(where: { !$0.isWhitespace })
        guard letters >= 3, term.contains(where: \.isLowercase) else { return nil }

        var chosen = self.chooseFamilyGaps(chars: chars, letters: letters)
        if chosen.count < self.targetGapCount(letters: letters) {
            // Top up with at most one bare vowel. Letting vowels fill freely
            // was measured and rejected: it turns `dishwasher` into
            // `d ___ shw ___ sh ___`, which no longer reads as a word.
            if let vowel = self.vowelCandidates(chars: chars, from: 2)
                .first(where: { self.fits($0, with: chosen, letters: letters) })
            {
                chosen.append(vowel)
            }
        }
        if chosen.isEmpty {
            // Last resort so no English word is left without a question. Short
            // words land here, and a/e/i/o/u are honest distractors for them
            // (beg / big / bog / bug are all real words).
            guard let vowel = self.vowelCandidates(chars: chars, from: 1).first else { return nil }
            chosen = [vowel]
        }
        chosen.sort { $0.range.lowerBound < $1.range.lowerBound }
        return self.assemble(chars: chars, term: term, chosen: chosen)
    }

    /// Greedy fill from the confusable table, re-ranking after each pick so the
    /// length-match preference sees what has already been taken.
    private nonisolated static func chooseFamilyGaps(chars: [Character], letters: Int) -> [Candidate] {
        let all = self.familyCandidates(chars: chars, letters: letters)
        let want = self.targetGapCount(letters: letters)
        let middle = Double(chars.count) / 2
        var chosen: [Candidate] = []
        while chosen.count < want {
            let usable = all.filter { self.fits($0, with: chosen, letters: letters) }
            guard !usable.isEmpty else { break }
            let lengths = Set(chosen.map(\.length))
            let best = usable.min { lhs, rhs in
                self.ranking(lhs, lengths: lengths, middle: middle)
                    < self.ranking(rhs, lengths: lengths, middle: middle)
            }
            guard let best else { break }
            chosen.append(best)
        }
        return chosen
    }

    /// Why one candidate beats another, in order: ① a gap the same length as
    /// the ones already taken (a mixed-length pool hints which option belongs
    /// where), ② vowel families before consonant ones, ③ table order,
    /// ④ nearest the middle of the word — without that one every gap piles up
    /// at the end (`refrigerat ___`) — and ⑤ position, so the order is total
    /// and the result is reproducible across runs.
    private nonisolated struct Ranking: Comparable {
        let lengthMismatch: Bool
        let tier: Int
        let rank: Int
        let distanceFromMiddle: Double
        let position: Int

        static func < (lhs: Self, rhs: Self) -> Bool {
            if lhs.lengthMismatch != rhs.lengthMismatch { return !lhs.lengthMismatch }
            if lhs.tier != rhs.tier { return lhs.tier < rhs.tier }
            if lhs.rank != rhs.rank { return lhs.rank < rhs.rank }
            if lhs.distanceFromMiddle != rhs.distanceFromMiddle {
                return lhs.distanceFromMiddle < rhs.distanceFromMiddle
            }
            return lhs.position < rhs.position
        }
    }

    private nonisolated static func ranking(
        _ candidate: Candidate,
        lengths: Set<Int>,
        middle: Double
    )
        -> Ranking
    {
        let centre = Double(candidate.range.lowerBound + candidate.range.upperBound) / 2
        return Ranking(
            lengthMismatch: !(lengths.isEmpty || lengths.contains(candidate.length)),
            tier: candidate.tier,
            rank: candidate.rank,
            distanceFromMiddle: abs(centre - middle),
            position: candidate.range.lowerBound
        )
    }

    /// Can this candidate join the ones already chosen?
    ///
    /// Gaps may not touch: at least one visible letter has to survive between
    /// them, or two adjacent blanks read as one wide one. Two gaps may not want
    /// the same answer either — the pool would show the option twice.
    private nonisolated static func fits(_ candidate: Candidate, with chosen: [Candidate], letters: Int) -> Bool {
        let blanked = chosen.reduce(candidate.length) { $0 + $1.length }
        guard Double(blanked) <= Double(letters) * self.maxBlankedShare else { return false }
        for taken in chosen {
            guard candidate.answer != taken.answer else { return false }
            let clear = candidate.range.lowerBound > taken.range.upperBound
                || candidate.range.upperBound < taken.range.lowerBound
            guard clear else { return false }
        }
        return true
    }

    private nonisolated static func familyCandidates(chars: [Character], letters: Int) -> [Candidate] {
        var out: [Candidate] = []
        let families = [self.vowelFamilies, self.consonantFamilies]
        for (tier, table) in families.enumerated() {
            for (rank, family) in table.enumerated() {
                for member in family where member.count >= 2 {
                    out += self.matches(of: member, in: chars, letters: letters)
                        .map { Candidate(range: $0, answer: member, family: family, tier: tier, rank: rank) }
                }
            }
        }
        return out
    }

    /// Exact-case occurrences of `member`, minus the positions the placement
    /// rules forbid. Matching on the original case rather than a lowercased
    /// copy keeps `Aquarius`-style capitals out of the answer, so an option
    /// always prints exactly as the family declares it.
    private nonisolated static func matches(of member: String, in chars: [Character], letters: Int) -> [Range<Int>] {
        let needle = Array(member)
        guard needle.count < letters, chars.count > needle.count else { return [] }
        var out: [Range<Int>] = []
        // Never start at 0: the opening letters are what makes the word
        // recognisable with a hole in it.
        for start in 1...(chars.count - needle.count) {
            let range = start..<(start + needle.count)
            guard !chars[range].contains(where: \.isWhitespace) else { continue }
            guard Array(chars[range]) == needle else { continue }
            out.append(range)
        }
        return out
    }

    /// Single-vowel candidates, latest first so a top-up lands away from the
    /// opening. `from` is the earliest index allowed: 2 when topping up beside
    /// real gaps, 1 for the last-resort solo gap on a short word.
    private nonisolated static func vowelCandidates(chars: [Character], from: Int) -> [Candidate] {
        guard chars.count > from + 1 else { return [] }
        var out: [Candidate] = []
        for index in from..<(chars.count - 1) {
            guard self.vowels.contains(chars[index]) else { continue }
            guard !chars[index - 1].isWhitespace, !chars[index + 1].isWhitespace else { continue }
            out.append(
                Candidate(
                    range: index..<(index + 1),
                    answer: String(chars[index]),
                    family: self.vowels.sorted().map(String.init),
                    tier: 2,
                    rank: 0
                )
            )
        }
        return out
    }

    private nonisolated static func assemble(chars: [Character], term: String, chosen: [Candidate]) -> SpellGaps {
        var segments: [String] = []
        var cursor = 0
        for candidate in chosen {
            segments.append(String(chars[cursor..<candidate.range.lowerBound]))
            cursor = candidate.range.upperBound
        }
        segments.append(String(chars[cursor...]))
        return SpellGaps(
            term: term,
            segments: segments,
            gaps: chosen.map { Gap(answer: $0.answer, range: $0.range) },
            options: self.buildOptions(for: chosen)
        )
    }

    /// Answers first, then distractors drawn round-robin from each gap's own
    /// family so every gap contributes a look-alike, topped up from the
    /// same-length generic pool when the families run dry.
    private nonisolated static func buildOptions(for chosen: [Candidate]) -> [String] {
        var options = chosen.map(\.answer)
        let target = min(options.count + self.distractorCount, self.maxOptions)

        var queues = chosen.map { candidate in
            candidate.family.filter { $0 != candidate.answer }
        }
        var drained = false
        while options.count < target, !drained {
            drained = true
            for index in queues.indices where options.count < target {
                guard !queues[index].isEmpty else { continue }
                drained = false
                let option = queues[index].removeFirst()
                guard !options.contains(option) else { continue }
                options.append(option)
            }
        }

        for candidate in chosen where options.count < target {
            for filler in self.genericChunks[candidate.length] ?? [] where options.count < target {
                guard !options.contains(filler) else { continue }
                options.append(filler)
            }
        }
        return options
    }
}

// MARK: - Display order

extension SpellGaps {
    /// The pool as the view draws it — deterministic per (item, attempt) so
    /// re-renders don't reshuffle mid-task, but a retry gets a new order.
    /// The gaps themselves never move between attempts: the chunk they got
    /// wrong is the one worth asking again.
    ///
    /// Main-actor isolated, unlike the placement above: it reads
    /// `studyStableHash`, which the module's default isolation puts on the main
    /// actor. See the same note on `TileBoard.units`.
    static func options(for item: StudyQueueItem, attempt: Int) -> [String] {
        guard let gaps = SpellGaps.of(term: TileBoard.spellSubject(for: item).text) else { return [] }
        var rng = SeededRNG(seed: studyStableHash("\(item.id)#gap#\(attempt)"))
        return gaps.options.shuffled(using: &rng)
    }
}
