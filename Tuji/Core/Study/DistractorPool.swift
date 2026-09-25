// Four-option assembly, with the same exclusion rules as the server and Android.
import Foundation

/// Four labels from the server candidate pool, or local vocabulary for old queues.
/// StudyChoiceSession owns the fresh round seed, stable presentation and retry history.
/// Unknown legacy labels are never used to guess a vocabulary's language.
func studyChoices(
    for item: StudyQueueItem,
    pool: [CardWord],
    session: TargetLanguage,
    variant: Int = 0,
    seed: UInt32? = nil,
    previous: [String] = []
)
    -> [String]
{
    let language = item.word.language(in: session)
    let target = StudyChoiceCandidate(
        wordId: item.id,
        label: item.word.word,
        language: language,
        gloss: item.word.chinese,
        category: item.word.category,
        pos: nil,
        exclusions: item.choiceExclusions,
        tier: 0,
        weight: 1
    )
    let local = pool.filter { $0.language(in: session) == language }.map { word in
        StudyChoiceCandidate(
            wordId: word.id,
            label: word.word,
            language: language,
            gloss: word.chinese,
            category: word.category,
            pos: nil,
            exclusions: [],
            tier: word.category == target.category ? 2 : 3,
            weight: 1
        )
    }
    // Old cached labels are used only if a same-language vocabulary entry can
    // identify them. Unknown labels cannot silently introduce the wrong language.
    let known = local + StudyChoiceData.reserve.filter { $0.language == language }
    let legacy = (item.choices ?? []).compactMap { label in
        known.first { choiceKey($0.label) == choiceKey(label) }
    }
    let server = item.choiceCandidates ?? []
    let candidates = prepareChoiceCandidates(target: target, input: server)
        .count >= 3 ? server : server + local + legacy
    return assembleStudyChoices(
        target: target,
        candidates: candidates,
        seed: seed ?? choiceHash("\(language.rawValue):\(item.id):\(variant)"),
        previous: previous
    )
}

/// Why a label may not stand beside the answer — or that it may.
///
/// A returned *value*, not a private `Bool`. The four rules were the reason
/// this module exists and every one of them was unreachable: they lived in
/// file-private functions with no test file, assertable only through a seeded
/// shuffle, by absence. The most valuable logic here sat behind the least
/// testable door.
enum DistractorFairness: Equatable {
    case fair
    /// The label *is* the answer, modulo case.
    case sameTerm
    /// One term's word tokens contain the other's: knife / kitchen knife.
    case tokenSubset
    /// CJK has no token boundaries, so substring stands in: 時計 / 腕時計.
    case cjkSubstring
    /// The dictionary translates both identically: pan / frying pan → 平底鍋.
    case sharedGloss
    case synonym
}

/// The fairness question for one question's answer, against one dictionary.
///
/// Built once per call rather than per candidate: the gloss index is a full
/// pass over the pool.
struct DistractorPool {
    let answer: String
    private let answerGlosses: Set<String>
    private let glossIndex: [String: Set<String>]

    init(answer: String, gloss: String, pool: [CardWord]) {
        self.answer = answer
        self.answerGlosses = chineseGlosses(gloss)
        self.glossIndex = buildGlossIndex(pool)
    }

    /// A distractor is unfair when a learner who knows the answer could
    /// legitimately pick it.
    func fairness(of label: String) -> DistractorFairness {
        if choiceKey(label) == choiceKey(self.answer) {
            return .sameTerm
        }
        if choiceAliasesConflict(label, self.answer) { return .synonym }
        let answerTokens = wordTokens(self.answer)
        let labelTokens = wordTokens(label)
        if !answerTokens.isEmpty, !labelTokens.isEmpty,
           answerTokens.isSubset(of: labelTokens) || labelTokens.isSubset(of: answerTokens)
        {
            return .tokenSubset
        }
        if containsCJK(label) || containsCJK(self.answer) {
            let a = self.answer.lowercased()
            let l = label.lowercased()
            if a.contains(l) || l.contains(a) { return .cjkSubstring }
        }
        if !self.answerGlosses.isEmpty,
           let glosses = glossIndex[choiceKey(label)],
           !glosses.isDisjoint(with: self.answerGlosses)
        {
            return .sharedGloss
        }
        return .fair
    }
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
        index[choiceKey(word.word), default: []].formUnion(chineseGlosses(word.chinese))
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
