// The language a word teaches — the "target" half of a learning direction.
// Raw values are the wire strings the backend sends in `targetLanguage`
// fields and uses as word_terms.language keys, so model fields decode
// straight into the enum. The value set is pinned by LearningDirection
// (adding a language is a coordinated client+server change, same as adding
// a direction), so strict decoding matches the existing pattern.
//
// `nonisolated`: pure value enum whose synthesized conformances must stay
// usable from nonisolated contexts (Codable decode paths, the coordinator's
// nonisolated task helpers) under the project's MainActor default isolation.

import Foundation

nonisolated enum TargetLanguage: String, Codable, Hashable, CaseIterable {
    case en
    case ja

    /// Human-readable name, for surfaces that show more than one language at
    /// once (the author profile groups its items this way). Resolved through
    /// `tujiLocalized` rather than a `LocalizedStringKey`, because the value
    /// comes from a decoded model and so would otherwise miss the uiLang switch.
    var label: String {
        switch self {
        case .ja: tujiLocalized("日文")
        case .en: tujiLocalized("英文")
        }
    }
}

/// Word payloads that can tell which language they teach. One shared
/// resolution so display / speech / distractor call sites can't drift.
nonisolated protocol LanguageTagged {
    var targetLanguage: TargetLanguage? { get }
    var reading: String? { get }
}

extension LanguageTagged {
    /// What the *payload* says: the explicit server tag wins, else a kana
    /// `reading` (a JA-only backend field) marks it Japanese. nil when it
    /// carries neither — older caches, and just-captured 自製圖鑑 words.
    ///
    /// Not for callers. Ask `language(in:)`, which is total; this is the half of
    /// the answer that lives on the word, exposed so the resolution can be tested
    /// against a payload directly.
    var taggedLanguage: TargetLanguage? {
        if let targetLanguage { return targetLanguage }
        if let reading, !reading.isEmpty { return .ja }
        return nil
    }

    /// The word's language. Always an answer.
    ///
    /// The fallback used to be the caller's job, stated in a doc comment: eleven
    /// of thirteen call sites never did it, so an untagged word read as English
    /// everywhere — the wrong half of a coin flip for a payload whose commonest
    /// source is a Japanese learner's own capture. `session` is 當前圖鑑語言, which
    /// a View reads from `\.targetLanguage` and a model takes as an input.
    ///
    /// A word's own tag still wins over the session, so a JA custom word speaks
    /// and sets Japanese inside an 英文 session.
    func language(in session: TargetLanguage) -> TargetLanguage {
        self.taggedLanguage ?? session
    }
}

extension CardWord: LanguageTagged {}
extension Word: LanguageTagged {}
extension StudyQueueWord: LanguageTagged {}

/// `headwordPronunciation` only exists because the witness types disagree:
/// `Word` stores it optional, the other two do not, and Swift will not accept a
/// `String` property as a `String?` requirement.
extension CardWord: Headworded {
    var headwordPronunciation: String? {
        self.pronunciation
    }
}

extension Word: Headworded {
    var headwordPronunciation: String? {
        self.pronunciation
    }
}

extension StudyQueueWord: Headworded {
    var headwordPronunciation: String? {
        self.pronunciation
    }
}
