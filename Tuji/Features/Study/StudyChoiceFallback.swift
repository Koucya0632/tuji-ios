// MCQ option assembly for the study flows (identify + review).
//
// `studyChoices` is the single entry point: it scrubs the server-attached
// `choices` of unfair near-synonyms of the answer, then tops the set back up
// from the local dictionary pool. Custom 自制圖鑑 cards (no server choices)
// build the whole set from the pool.
//
// Why the scrub exists: the server distractor draw is category-scoped, so a
// 平底鍋 question could offer both "pan" (the answer) and "frying pan" (a
// distractor) — two words the dictionary translates identically. A learner
// who knows the word can still be marked wrong. Unfair = shares a Chinese
// gloss with the answer, or one term's tokens contain the other's
// ("knife" vs "kitchen knife").
//
// The order must be STABLE across SwiftUI re-renders: `computedChoices` is a
// computed property re-evaluated on every redraw, so a plain `.shuffled()`
// would make the options jump. We seed a deterministic RNG from the item id
// (via FNV-1a, which — unlike Swift's per-process-seeded Hasher — is stable
// across launches too), so the same card always yields the same layout.

import Foundation

/// Up to four MCQ option labels for `item`: the correct answer plus fair
/// distractors. Server-provided `choices` are preferred (scrubbed), then the
/// set is topped up from `pool`. The correct label is `item.word.word` (what
/// the review / identify coordinators compare picks against).
///
/// `variant` folds into the seed: the coordinator bumps it per wrong attempt
/// so a requeued question re-shuffles (and may re-draw top-ups) — otherwise
/// remembering "the answer was C" stands in for knowing the word.
func studyChoices(for item: StudyQueueItem, pool: [CardWord], variant: Int = 0) -> [String] {
    let answer = item.word.word
    var rng = SeededRNG(seed: studyStableHash(item.id) &+ UInt64(variant) &* 0x9E3779B97F4A7C15)
    let answerGlosses = chineseGlosses(item.word.chinese)
    let glossIndex = buildGlossIndex(pool)
    var seen: Set<String> = [answer.lowercased()]
    var distractors: [String] = []

    func admit(_ label: String) {
        guard distractors.count < 3,
              !label.isEmpty,
              isFairDistractor(label, answer: answer, answerGlosses: answerGlosses, glossIndex: glossIndex),
              seen.insert(label.lowercased()).inserted
        else { return }
        distractors.append(label)
    }

    // Server distractors first — they're difficulty-curated (same category).
    for label in item.choices ?? [] {
        admit(label)
    }

    // Top up from the local dictionary, same-language first. `wordLanguage`
    // so untagged custom words still land in the right half of the pool.
    if distractors.count < 3 {
        if let lang = item.word.wordLanguage {
            for word in pool.filter({ $0.wordLanguage == lang }).shuffled(using: &rng) {
                admit(word.word)
            }
        }
        if distractors.count < 3 {
            // Same-language pool was thin (e.g. brand-new account) — widen to
            // all words so the quiz still has plausible-ish options.
            for word in pool.shuffled(using: &rng) {
                admit(word.word)
            }
        }
    }

    return ([answer] + distractors).shuffled(using: &rng)
}

/// A distractor is unfair when a learner who knows the answer could
/// legitimately pick it: it shares a Chinese gloss with the answer
/// (pan / frying pan → both 平底鍋), or one term's word tokens contain the
/// other's (knife / kitchen knife / table knife), or — for CJK terms without
/// token boundaries — one string contains the other (時計 / 腕時計).
private func isFairDistractor(
    _ label: String,
    answer: String,
    answerGlosses: Set<String>,
    glossIndex: [String: Set<String>]
)
    -> Bool
{
    if label.compare(answer, options: [.caseInsensitive]) == .orderedSame { return false }
    let answerTokens = wordTokens(answer)
    let labelTokens = wordTokens(label)
    if !answerTokens.isEmpty, !labelTokens.isEmpty,
       answerTokens.isSubset(of: labelTokens) || labelTokens.isSubset(of: answerTokens)
    {
        return false
    }
    if containsCJK(label) || containsCJK(answer) {
        let a = answer.lowercased()
        let l = label.lowercased()
        if a.contains(l) || l.contains(a) { return false }
    }
    if !answerGlosses.isEmpty,
       let glosses = glossIndex[label.lowercased()],
       !glosses.isDisjoint(with: answerGlosses)
    {
        return false
    }
    return true
}

/// Lowercased word tokens ("kitchen knife" → {kitchen, knife}). CJK terms
/// come back as a single token; the substring rule covers those instead.
private func wordTokens(_ term: String) -> Set<String> {
    Set(
        term.lowercased()
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .map(String.init)
    )
}

/// Individual Chinese glosses from a dictionary `chinese` field, which packs
/// synonyms as "鍋子 / 湯鍋" or "爐子／瓦斯爐" style lists.
private func chineseGlosses(_ chinese: String) -> Set<String> {
    Set(
        chinese
            .split(whereSeparator: { "/／、,，;；".contains($0) })
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    )
}

private func containsCJK(_ s: String) -> Bool {
    s.unicodeScalars.contains { scalar in
        (0x4E00...0x9FFF).contains(scalar.value) // CJK Unified Ideographs
            || (0x3040...0x30FF).contains(scalar.value) // hiragana + katakana
    }
}

/// Term → union of Chinese glosses across the dictionary (a label can exist
/// in both EN and JA decks).
private func buildGlossIndex(_ pool: [CardWord]) -> [String: Set<String>] {
    var index: [String: Set<String>] = [:]
    for word in pool {
        index[word.word.lowercased(), default: []].formUnion(chineseGlosses(word.chinese))
    }
    return index
}

/// SplitMix64 — a tiny, fast value-type RNG so `shuffled(using:)` is
/// reproducible for a given seed. Internal: the new-flow coordinator reuses it
/// for tile scrambles.
struct SeededRNG: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        self.state = seed
    }

    mutating func next() -> UInt64 {
        self.state &+= 0x9E3779B97F4A7C15
        var z = self.state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}

/// FNV-1a 64-bit hash of a string — stable across process launches, so
/// anything derived from it (option order, spell variant, tile scramble)
/// doesn't change between app runs or SwiftUI re-renders.
func studyStableHash(_ string: String) -> UInt64 {
    var hash: UInt64 = 0xCBF29CE484222325
    for byte in string.utf8 {
        hash ^= UInt64(byte)
        hash = hash &* 0x00000100000001B3
    }
    return hash
}
