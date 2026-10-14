// 助手 — what the user asked for, before anything is looked up.
//
// Tier one has no model, so "understanding" is a keyword table. That is honest
// only if the table is small and its fallback is useful: anything it does not
// recognise is treated as a word to look up, which is the one question this
// screen can always attempt. A reply of "I didn't understand" is reserved for
// input that is empty once the command words are taken out.
//
// The keywords are spelled here, in every interface language at once, rather
// than in the string catalogue: what someone types has nothing to do with the
// language the app is set to.

import Foundation

enum AssistantIntent: Hashable {
    /// 「查單字」 with no word yet.
    case lookupPrompt
    case lookup(query: String)
    /// Send this question to the model. Never produced by `parse` — it only
    /// exists as a chip the person taps, because it is the one intent that
    /// costs 罐頭點數 and a keyword rule must not be able to spend them.
    case askModel(question: String)
}

extension AssistantIntent {
    /// Reads free text. `nil` only for blank input — there is nothing to answer.
    static func parse(_ text: String) -> AssistantIntent? {
        let needle = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !needle.isEmpty else { return nil }

        let query = Self.lookupQuery(from: needle)
        if query.isEmpty || Self.wordWords.contains(query) { return .lookupPrompt }
        return .lookup(query: query)
    }

    /// Strips the command around a word: 「查 apple」「apple 是什麼」 → `apple`.
    private static func lookupQuery(from needle: String) -> String {
        // Padding goes first as well as last: 「…是什麼意思？」 ends in a
        // question mark, not in the suffix.
        var query = needle.trimmingCharacters(in: Self.queryPadding)
        if let prefix = Self.lookupPrefixes.first(where: { query.hasPrefix($0) }) {
            query = String(query.dropFirst(prefix.count))
        }
        if let suffix = Self.lookupSuffixes.first(where: { query.hasSuffix($0) }) {
            query = String(query.dropLast(suffix.count))
        }
        return query.trimmingCharacters(in: Self.queryPadding)
    }

    private static let queryPadding = CharacterSet.whitespacesAndNewlines
        .union(CharacterSet(charactersIn: "「」『』\"'“”？?。.！!：:"))

    private static let wordWords: Set<String> = [
        "單字", "单字", "詞", "词", "詞條", "词条", "word", "words", "a word", "単語",
        // A command with nothing after it.
        "search", "find", "look up", "lookup"
    ]
    /// Longest first within a family, so 「查詢」 is not read as 「查」 + 「詢」.
    private static let lookupPrefixes = [
        "查詢", "查询", "查一下", "查", "搜尋", "搜索", "look up ", "lookup ", "search for ", "search ",
        "find ", "検索", "調べて"
    ]
    private static let lookupSuffixes = [
        "是什麼意思", "是什么意思", "是什麼", "是什么", "的意思", "ってなに", "って何", "とは", " meaning"
    ]
}

extension AssistantIntent {
    /// The label on a quick-reply chip, and what the user is shown having said
    /// when they tap it.
    var chipTitle: String {
        switch self {
        case .lookupPrompt: tujiLocalized("查單字")
        case let .lookup(query): tujiLocalized("查「\(query)」這個詞")
        case .askModel: tujiLocalized("問 AI")
        }
    }
}
