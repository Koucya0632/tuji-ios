// What 求救提示 turns the picture over to.
//
// The hint used to be `word.chinese`, always. For a zh reader that is the answer
// translated — 水桶 — so the hint and the answer were one fact in two languages,
// and the flip taught nothing it did not also give away. The 釋義 is the better
// prompt: 附提把、開口朝上的圓柱形容器. It was already on the detail page, two taps
// further in; now it comes on the payload (lib/study-hint.ts).
//
// Two cases rather than one string, because the two are *read* differently — a
// 釋義 is prose and sets as body text, a gloss is a word and sets as a headline.
// The typography stays in the view; which of the two the card has is decided
// here, where a test can reach it.
//
// The rule is one line, and the reason it can be one line is that the server
// already refuses to send a 釋義 that repeats the gloss. That equality is
// monolingual study (UI language == target language), where the gloss *is* the
// explanatory definition, written in the language being tested — the one thing
// this face may not carry, and the same prohibition that keeps `reading` and
// `pronunciation` off it (ADR-0007). Re-deriving that here would mean asking the
// UI language and the target language a question the server has already
// answered, and a rule stated in two places is a rule that can disagree with
// itself.

import Foundation

enum HintFace: Equatable {
    /// One explanatory sentence in the reader's own language.
    case definition(String)
    /// The one-line gloss, which is what the flip showed before there was a
    /// 釋義 to show, and what it still shows for a word without one.
    case gloss(String)

    init(_ word: StudyQueueWord) {
        let definition = word.definition?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let gloss = word.chinese
        self = definition.isEmpty || definition == gloss.trimmingCharacters(in: .whitespacesAndNewlines)
            ? .gloss(gloss)
            : .definition(definition)
    }

    /// The text on the face — and the text VoiceOver reads, which is the same
    /// string for the same reason the label follows the face at all.
    var text: String {
        switch self {
        case let .definition(text), let .gloss(text): text
        }
    }
}
