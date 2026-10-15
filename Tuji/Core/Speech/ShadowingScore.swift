// 跟讀 — how much of a line the speech recogniser heard.
//
// This is not a pronunciation grade. On-device recognition only says what it
// thinks was said, so the score answers "would a listener have caught these
// words", not "was the accent right". That is the honest claim the copy makes.
//
// Both sides go through the same normalisation, which is the point of it:
//
// - Japanese comes back from the recogniser in whatever mix of kanji and kana
//   it likes (傘 / かさ / カサ), so both the line and the transcript are cut into
//   words by `CFStringTokenizer` and each word is turned into hiragana through
//   its Latin transcription. The tokenizer may read a kanji wrongly, but it
//   reads it the same wrong way on both sides. Hiragana rather than romaji
//   because romaji is mostly the same five vowels, and a longest common
//   subsequence over it credits sounds that were never said.
// - English is compared word by word, lowercased, punctuation dropped.
//
// A word of the line counts as heard when most of its characters appear, in
// order, in what was heard. Punctuation is not scored either way.

import Foundation

nonisolated struct ShadowingScore: Equatable {
    struct Word: Equatable {
        /// As written in the line.
        let surface: String
        let heard: Bool
    }

    /// The line's scored words, in order. Punctuation is left out.
    let words: [Word]
    /// 0…1: the share of the line that was heard — by kana for Japanese, where
    /// a word is a few sounds, and by word for English, where counting letters
    /// lets one long word outweigh the rest of the sentence.
    let ratio: Double

    enum Verdict: Equatable {
        case great, close, again
    }

    var verdict: Verdict {
        if self.ratio >= 0.85 { return .great }
        if self.ratio >= 0.6 { return .close }
        return .again
    }

    var missed: [String] {
        self.words.filter { !$0.heard }.map(\.surface)
    }

    /// Missed words that sit next to each other, run together into one phrase:
    /// the tokenizer cuts 置いてね into three pieces, and listing them one by
    /// one reads as noise. `joiner` is what goes between two words of the
    /// line's language — nothing for Japanese, a space for English.
    func missedPhrases(joiner: String) -> [String] {
        var phrases: [String] = []
        var current: [String] = []
        for word in self.words {
            if word.heard {
                if !current.isEmpty { phrases.append(current.joined(separator: joiner)) }
                current = []
            } else {
                current.append(word.surface)
            }
        }
        if !current.isEmpty { phrases.append(current.joined(separator: joiner)) }
        return phrases
    }

    /// Below this share of its characters a word is not counted as heard.
    private static let wordThreshold = 0.6

    init(words: [Word], ratio: Double) {
        self.words = words
        self.ratio = ratio
    }

    init(target: String, heard: String, language: TargetLanguage) {
        let line = Self.units(target, language: language)
        let spoken = Self.units(heard, language: language)
        switch language {
        case .ja:
            let flags = Self.matchedFlags(
                Array(line.map(\.key).joined()),
                Array(spoken.map(\.key).joined())
            )
            var words: [Word] = []
            var heardCount = 0
            var offset = 0
            for unit in line {
                let count = unit.key.count
                let hit = flags[offset..<offset + count].filter(\.self).count
                heardCount += hit
                offset += count
                words.append(Word(surface: unit.surface, heard: Double(hit) >= Double(count) * Self.wordThreshold))
            }
            let total = line.reduce(0) { $0 + $1.key.count }
            self.init(words: words, ratio: total == 0 ? 0 : Double(heardCount) / Double(total))
        case .en:
            let flags = Self.matchedFlags(line.map(\.key), spoken.map(\.key))
            let words = zip(line, flags).map { Word(surface: $0.surface, heard: $1) }
            let heardCount = flags.filter(\.self).count
            self.init(words: words, ratio: line.isEmpty ? 0 : Double(heardCount) / Double(line.count))
        }
    }

    // MARK: - Normalisation

    struct Unit: Equatable {
        let surface: String
        /// What is compared: hiragana for Japanese, a lowercased word for English.
        let key: String
    }

    /// The line cut into scorable words. Units with nothing to compare —
    /// punctuation, symbols — are dropped.
    static func units(_ text: String, language: TargetLanguage) -> [Unit] {
        switch language {
        case .en:
            text.split(whereSeparator: { $0.isWhitespace }).compactMap { piece in
                let key = piece.lowercased().filter { $0.isLetter || $0.isNumber || $0 == "'" }
                    .trimmingCharacters(in: CharacterSet(charactersIn: "'"))
                guard !key.isEmpty else { return nil }
                return Unit(surface: piece.trimmingCharacters(in: .punctuationCharacters), key: key)
            }
        case .ja:
            self.japaneseUnits(text)
        }
    }

    private static func japaneseUnits(_ text: String) -> [Unit] {
        let string = text as CFString
        let length = CFStringGetLength(string)
        guard length > 0 else { return [] }
        let tokenizer = CFStringTokenizerCreate(
            nil,
            string,
            CFRange(location: 0, length: length),
            kCFStringTokenizerUnitWordBoundary,
            Locale(identifier: "ja_JP") as CFLocale
        )
        var units: [Unit] = []
        while CFStringTokenizerAdvanceToNextToken(tokenizer).rawValue != 0 {
            let range = CFStringTokenizerGetCurrentTokenRange(tokenizer)
            let nsRange = NSRange(location: range.location, length: range.length)
            let surface = (text as NSString).substring(with: nsRange)
            let latin = CFStringTokenizerCopyCurrentTokenAttribute(
                tokenizer,
                kCFStringTokenizerAttributeLatinTranscription
            ) as? String
            let key = self.kana(surface: surface, latin: latin)
            guard !key.isEmpty else { continue }
            units.append(Unit(surface: surface, key: key))
        }
        return units
    }

    /// A word as hiragana, letters only. Kana already in the word is kept as is
    /// (folded to hiragana) — the Latin round trip only exists for kanji.
    private static func kana(surface: String, latin: String?) -> String {
        let source: String = if surface.unicodeScalars.contains(where: Self.isKanji), let latin {
            latin.applyingTransform(.latinToHiragana, reverse: false) ?? surface
        } else {
            surface.applyingTransform(.hiraganaToKatakana, reverse: true) ?? surface
        }
        return String(source.unicodeScalars.filter(Self.isComparable).map(Character.init))
    }

    private static func isKanji(_ scalar: Unicode.Scalar) -> Bool {
        (0x4E00...0x9FFF).contains(scalar.value) || (0x3400...0x4DBF).contains(scalar.value) || scalar == "々"
    }

    /// Hiragana, the long-vowel mark, and Latin letters or digits a line may
    /// carry (`OK`, `3`). Everything else is punctuation.
    private static func isComparable(_ scalar: Unicode.Scalar) -> Bool {
        (0x3041...0x3096).contains(scalar.value) || scalar == "ー"
            || CharacterSet.alphanumerics.contains(scalar) && !isKanji(scalar)
    }

    // MARK: - Alignment

    /// Which elements of `target` take part in a longest common subsequence
    /// with `heard`.
    static func matchedFlags<T: Equatable>(_ target: [T], _ heard: [T]) -> [Bool] {
        let n = target.count, m = heard.count
        guard n > 0 else { return [] }
        guard m > 0 else { return Array(repeating: false, count: n) }
        var table = Array(repeating: Array(repeating: 0, count: m + 1), count: n + 1)
        for i in stride(from: n - 1, through: 0, by: -1) {
            for j in stride(from: m - 1, through: 0, by: -1) {
                table[i][j] = target[i] == heard[j]
                    ? table[i + 1][j + 1] + 1
                    : max(table[i + 1][j], table[i][j + 1])
            }
        }
        var flags = Array(repeating: false, count: n)
        var i = 0, j = 0
        while i < n, j < m {
            if target[i] == heard[j] {
                flags[i] = true
                i += 1
                j += 1
            } else if table[i + 1][j] >= table[i][j + 1] {
                i += 1
            } else {
                j += 1
            }
        }
        return flags
    }
}
