import Foundation

func choiceKey(_ label: String) -> String {
    String(label.precomposedStringWithCompatibilityMapping.lowercased().unicodeScalars.filter {
        !CharacterSet.whitespacesAndNewlines.contains($0) && $0.properties.generalCategory != .dashPunctuation
    })
}

private func choiceTokens(_ label: String) -> Set<String> {
    Set(label.precomposedStringWithCompatibilityMapping.lowercased()
        .split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init))
}

private func choiceGlosses(_ gloss: String) -> Set<String> {
    Set(gloss.precomposedStringWithCompatibilityMapping.lowercased()
        .split(whereSeparator: { "/、,，;；".contains($0) })
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty })
}

private let choiceAliases = StudyChoiceData.aliases.map { Set($0.map(choiceKey)) }

func choiceAliasesConflict(_ a: String, _ b: String) -> Bool {
    let ak = choiceKey(a), bk = choiceKey(b)
    return choiceAliases.contains { $0.contains(ak) && $0.contains(bk) }
}

func choicesConflict(_ a: StudyChoiceCandidate, _ b: StudyChoiceCandidate) -> Bool {
    let ak = choiceKey(a.label), bk = choiceKey(b.label)
    if ak.isEmpty || bk.isEmpty || ak == bk { return true }
    if !a.wordId.isEmpty && a.wordId == b.wordId { return true }
    if choiceAliasesConflict(a.label, b.label) { return true }
    if (a.exclusions ?? []).contains(where: { choiceKey($0) == bk }) ||
        (b.exclusions ?? []).contains(where: { choiceKey($0) == ak }) { return true }
    let at = choiceTokens(a.label), bt = choiceTokens(b.label)
    if !at.isEmpty, !bt.isEmpty, at.isSubset(of: bt) || bt.isSubset(of: at) { return true }
    let cjk = (ak + bk).unicodeScalars.contains {
        (0x3040...0x30FF).contains($0.value) || (0x4E00...0x9FFF).contains($0.value)
    }
    if cjk, ak.contains(bk) || bk.contains(ak) { return true }
    return !choiceGlosses(a.gloss).isDisjoint(with: choiceGlosses(b.gloss))
}

private func choiceBefore(_ a: StudyChoiceCandidate, _ b: StudyChoiceCandidate) -> Bool {
    if a.tier != b.tier { return a.tier < b.tier }
    if a.weight != b.weight { return a.weight > b.weight }
    return choiceKey(a.label) < choiceKey(b.label)
}

func prepareChoiceCandidates(target: StudyChoiceCandidate, input: [StudyChoiceCandidate]) -> [StudyChoiceCandidate] {
    var merged: [String: StudyChoiceCandidate] = [:]
    for c in input {
        let key = "\(c.language.rawValue):\(choiceKey(c.label))"
        guard let old = merged[key] else { merged[key] = c
            continue
        }
        let preferred = choiceBefore(c, old) ? c : old
        merged[key] = StudyChoiceCandidate(
            wordId: preferred.wordId,
            label: preferred.label,
            language: preferred.language,
            gloss: [old.gloss, c.gloss].filter { !$0.isEmpty }.joined(separator: " / "),
            category: preferred.category,
            pos: preferred.pos,
            exclusions: Array(Set((old.exclusions ?? []) + (c.exclusions ?? []))),
            tier: preferred.tier,
            weight: preferred.weight
        )
    }
    var result: [StudyChoiceCandidate] = []
    var counts: [Int: Int] = [:]
    for c in merged.values.sorted(by: choiceBefore) {
        guard c.language == target.language, c.weight.isFinite, c.weight > 0,
              (1...4).contains(c.tier), counts[c.tier, default: 0] < 12,
              !choicesConflict(target, c), !result.contains(where: { choicesConflict($0, c) })
        else { continue }
        result.append(c)
        counts[c.tier, default: 0] += 1
    }
    return result
}

struct ChoiceRandom {
    var state: UInt32
    mutating func next() -> Double {
        self.state = self.state &* 1_664_525 &+ 1_013_904_223
        return Double(self.state) / 4_294_967_296
    }
}

func choiceHash(_ text: String) -> UInt32 {
    var hash: UInt32 = 2_166_136_261
    for b in text.utf8 {
        hash = (hash ^ UInt32(b)) &* 16_777_619
    }
    return hash
}

func assembleStudyChoices(
    target: StudyChoiceCandidate,
    candidates: [StudyChoiceCandidate],
    seed: UInt32,
    previous: [String] = []
)
    -> [String]
{
    let pool = prepareChoiceCandidates(target: target, input: candidates + StudyChoiceData.reserve)
    var rng = ChoiceRandom(state: seed)
    var picked: [StudyChoiceCandidate] = []
    let old = Set(previous.filter { choiceKey($0) != choiceKey(target.label) }.map(choiceKey))
    func draw(_ limit: Int, freshOnly: Bool) {
        for tier in 1...4 {
            var available = pool
                .filter { $0.tier == tier && !picked.contains($0) && (!freshOnly || !old.contains(choiceKey($0.label)))
                }
            while picked.count < limit, !available.isEmpty {
                var ticket = rng.next() * available.reduce(0) { $0 + $1.weight }
                var i = 0
                while i < available.count - 1 {
                    ticket -= available[i].weight
                    if ticket < 0 { break }
                    i += 1
                }
                picked.append(available.remove(at: i))
            }
        }
    }
    if !old.isEmpty { draw(2, freshOnly: true) }
    draw(3, freshOnly: false)
    // Release coverage checks every published word against the bundled pool.
    assert(picked.count == 3, "Insufficient fair study choices: \(target.wordId)")
    var result = [target.label] + picked.map(\.label)
    for i in stride(from: result.count - 1, through: 1, by: -1) {
        result.swapAt(i, Int(rng.next() * Double(i + 1)))
    }
    return result
}

/// One instance per learning/review round. Cache the actual displayed choices,
/// not just a seed: a catalogue update while answering must not replace them.
final class StudyChoiceSession {
    private let seed: UInt32
    private var snapshots: [String: [String]] = [:]
    private var previous: [String: [String]] = [:]
    init(seed: UInt32 = .random(in: .min ... .max)) {
        self.seed = seed
    }

    func choices(for item: StudyQueueItem, pool: [CardWord], session: TargetLanguage, variant: Int) -> [String] {
        let wordKey = "\(item.word.language(in: session).rawValue):\(item.id)"
        let key = "\(wordKey):\(variant)"
        if let cached = snapshots[key] { return cached }
        let result = studyChoices(
            for: item,
            pool: pool,
            session: session,
            variant: variant,
            seed: self.seed &+ choiceHash(key),
            previous: self.previous[wordKey] ?? []
        )
        snapshots[key] = result
        previous[wordKey] = result
        return result
    }
}
