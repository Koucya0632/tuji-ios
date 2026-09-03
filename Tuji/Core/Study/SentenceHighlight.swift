// Where the word being asked about sits inside its own example sentence.
//
// Done on the device, against the plain sentence, which is not the obvious
// choice — the server has 詞塊 with a resolved `word_id`, and that is exactly
// the argument that put `mentionedWordIds` on the payload. Measured against the
// live corpus, though, the spans are the *worse* source:
//
//     substring match   en 939/952   ja 945/952
//     span word_id      en 838/952   ja 894/952
//
// Spans only carry a `word_id` where the base form resolved, and a slice of the
// current sentences have no span rows at all. So the annotation would cost a
// third deploy to identify the target less often. Matching here is both better
// and free.
//
// The ~1% it misses are sentences that never spell the headword: `grater` in
// "grate a little fresh ginger", `scanner` in "Scan both sides", `ベッド` in
// 「夜11時に寝ます」. Those get no highlight, which is the right failure — a
// missing highlight is quieter than a wrong one, and nothing here can point at
// the wrong word.

import Foundation

enum SentenceHighlight {
    /// The slice of `sentence` that spells `word`, or nil when it does not.
    ///
    /// Case-insensitive, and for Latin-script headwords it demands a word
    /// boundary: without one, `cup` would light up inside `cupboard`. The
    /// boundary check is deliberately **not** applied to Japanese — kana and
    /// kanji are letters, so requiring a non-letter neighbour would reject
    /// every Japanese sentence there is.
    static func range(of word: String, in sentence: String) -> Range<String.Index>? {
        let needle = word.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty, !sentence.isEmpty else { return nil }
        // A headword written in ASCII is one whose script has spaces between
        // words. Everything else (kana, kanji) is matched as a plain substring.
        let latin = needle.allSatisfy(\.isASCII)

        var from = sentence.startIndex
        while let found = sentence.range(
            of: needle,
            options: .caseInsensitive,
            range: from..<sentence.endIndex
        ) {
            guard latin else { return found }
            if self.startsAWord(found.lowerBound, in: sentence),
               let end = self.wordEnd(after: found.upperBound, in: sentence)
            {
                return found.lowerBound..<end
            }
            from = found.upperBound
        }
        return nil
    }

    private static func startsAWord(_ index: String.Index, in sentence: String) -> Bool {
        guard index > sentence.startIndex else { return true }
        return !sentence[sentence.index(before: index)].isLetter
    }

    /// The end of the match, having swallowed a plural suffix if one is there.
    ///
    /// Ten sentences in the corpus name the word in the plural — "The traffic
    /// cones mark the work area", "Please open the curtains", "I have two
    /// monitors at my desk". Stopping at the singular would leave the last
    /// letter outside the highlighter, which looks like a rendering bug rather
    /// than a decision.
    ///
    /// Only `s` and `es`, never "any trailing letters": the loose version would
    /// stretch `grate` over `grater` and `cup` over `cupboard`, which is the
    /// wrong-word highlight this whole function is arranged to avoid.
    private static func wordEnd(after index: String.Index, in sentence: String) -> String.Index? {
        for suffix in ["es", "s"] {
            guard let after = sentence.index(
                index,
                offsetBy: suffix.count,
                limitedBy: sentence.endIndex
            )
            else { continue }
            guard sentence[index..<after].lowercased() == suffix else { continue }
            if after == sentence.endIndex || !sentence[after].isLetter { return after }
        }
        return index == sentence.endIndex || !sentence[index].isLetter ? index : nil
    }
}
