// MCQ option fallback for queue items the backend didn't attach `choices` to.
//
// The server builds distractors from the public deck pool (cards-db
// attachChoices), so 自制圖鑑 (custom) cards — whose answers live outside that
// pool — arrive with `choices == nil`. Rather than show a single-option MCQ,
// we synthesize a 4-option set on-device from the user's other words.
//
// The order must be STABLE across SwiftUI re-renders: `computedChoices` is a
// computed property re-evaluated on every redraw, so a plain `.shuffled()`
// would make the options jump. We seed a deterministic RNG from the item id
// (via FNV-1a, which — unlike Swift's per-process-seeded Hasher — is stable
// across launches too), so the same card always yields the same layout.

import Foundation

/// Up to four MCQ option labels for `item`: the correct answer plus distractors
/// drawn from `pool`. The correct label is `item.word.word` (what the review /
/// identify coordinators compare picks against). Prefers same-language
/// distractors and tops up across languages only if that pool is too thin.
func mcqFallbackChoices(for item: StudyQueueItem, pool: [CardWord]) -> [String] {
    let answer = item.word.word
    var rng = SeededRNG(seed: fnv1a(item.id))
    var seen: Set<String> = [answer]
    var distractors: [String] = []

    func collect(_ words: [CardWord]) {
        for word in words.shuffled(using: &rng) {
            guard distractors.count < 3 else { break }
            let label = word.word
            if !label.isEmpty, seen.insert(label).inserted {
                distractors.append(label)
            }
        }
    }

    if let lang = item.word.targetLanguage {
        collect(pool.filter { $0.targetLanguage == lang })
    }
    if distractors.count < 3 {
        // Same-language pool was thin (e.g. brand-new account) — widen to all
        // words so the quiz still has plausible-ish options.
        collect(pool)
    }
    return ([answer] + distractors).shuffled(using: &rng)
}

/// SplitMix64 — a tiny, fast value-type RNG so `shuffled(using:)` is
/// reproducible for a given seed.
private struct SeededRNG: RandomNumberGenerator {
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

/// FNV-1a 64-bit hash of a string — stable across process launches, so the
/// derived option order doesn't change between app runs.
private func fnv1a(_ string: String) -> UInt64 {
    var hash: UInt64 = 0xCBF29CE484222325
    for byte in string.utf8 {
        hash ^= UInt64(byte)
        hash = hash &* 0x00000100000001B3
    }
    return hash
}
