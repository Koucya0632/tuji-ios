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
}

/// Word payloads that can tell which language they teach. One shared
/// resolution so display / speech / distractor call sites can't drift.
nonisolated protocol LanguageTagged {
    var targetLanguage: TargetLanguage? { get }
    var reading: String? { get }
}

extension LanguageTagged {
    /// The word's own language: the explicit server tag wins, else a kana
    /// `reading` (a JA-only backend field) marks it Japanese. nil when the
    /// payload carries neither (older caches, just-captured custom words) —
    /// callers that need a definite answer fall back to the session's
    /// `learningDirection.targetLanguage`.
    var wordLanguage: TargetLanguage? {
        if let targetLanguage { return targetLanguage }
        if let reading, !reading.isEmpty { return .ja }
        return nil
    }
}

extension CardWord: LanguageTagged {}
extension Word: LanguageTagged {}
extension StudyQueueWord: LanguageTagged {}
