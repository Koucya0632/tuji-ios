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
    /// 「有哪些分類」.
    case categories
    /// One category, by id.
    case category(id: String)
    /// 「收藏」 with nothing narrower — the overview that offers the three kinds.
    case favorites
    case bookmarks
    /// 物見 cards the user saved (`saved:<slug>`).
    case savedCards
    case savedCollections
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
    static func parse(_ text: String, categories: [TujiCategory]) -> AssistantIntent? {
        let needle = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !needle.isEmpty else { return nil }

        // Narrowest first: 「收藏的合集」 contains 「收藏」 too.
        if Self.contains(needle, any: Self.collectionWords) { return .savedCollections }
        if Self.contains(needle, any: Self.bookmarkWords) { return .bookmarks }
        if Self.contains(needle, any: Self.sightingWords) { return .savedCards }
        if Self.contains(needle, any: Self.favoriteWords) { return .favorites }

        let asksForCategory = Self.contains(needle, any: Self.categoryWords)
        if let category = Self.category(named: needle, in: categories, loose: asksForCategory) {
            return .category(id: category.id)
        }
        if asksForCategory { return .categories }

        let query = Self.lookupQuery(from: needle)
        if query.isEmpty || Self.wordWords.contains(query) { return .lookupPrompt }
        return .lookup(query: query)
    }

    /// A category the text names. Exact by default — 「廚房」 is the category,
    /// 「廚房用具」 is a word to look up. `loose` (the text already said 分類)
    /// also accepts the name appearing anywhere, so 「廚房分類」 lands on it.
    private static func category(
        named needle: String,
        in categories: [TujiCategory],
        loose: Bool
    )
        -> TujiCategory?
    {
        let named = categories.map { category in
            (category, [category.nameZh, category.name, category.id].map { $0.lowercased() })
        }
        if let exact = named.first(where: { $0.1.contains(needle) }) { return exact.0 }
        guard loose else { return nil }
        return named.first { entry in
            entry.1.contains { !$0.isEmpty && needle.contains($0) }
        }?.0
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

    /// Does the text use one of these words?
    ///
    /// A Latin keyword has to start a word — `theme` is in `themes` and must
    /// not be found in `anthem`. CJK has no word breaks to respect, so there a
    /// keyword counts wherever it appears.
    private static func contains(_ needle: String, any words: [String]) -> Bool {
        let tokens = needle.split { !$0.isLetter && !$0.isNumber }
        return words.contains { word in
            word.allSatisfy(\.isASCII)
                ? tokens.contains { $0.hasPrefix(word) }
                : needle.contains(word)
        }
    }

    private static let queryPadding = CharacterSet.whitespacesAndNewlines
        .union(CharacterSet(charactersIn: "「」『』\"'“”？?。.！!：:"))

    private static let collectionWords = ["合集", "合辑", "collection", "コレクション"]
    private static let bookmarkWords = ["書籤", "书签", "bookmark", "ブックマーク", "しおり"]
    private static let sightingWords = ["物見", "物见", "sighting"]
    private static let favoriteWords = ["收藏", "favorite", "favourite", "saved", "お気に入り", "保存"]
    private static let categoryWords = [
        "分類", "分类", "主題", "主题", "category", "categories", "theme", "カテゴリ", "テーマ"
    ]
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
    var isLookup: Bool {
        switch self {
        case .lookup, .lookupPrompt: true
        default: false
        }
    }

    /// The label on a quick-reply chip, and what the user is shown having said
    /// when they tap it.
    var chipTitle: String {
        switch self {
        case .categories: tujiLocalized("看分類")
        case let .category(id): id
        case .favorites: tujiLocalized("我的收藏")
        case .bookmarks: tujiLocalized("書籤")
        case .savedCards: tujiLocalized("物見卡片")
        case .savedCollections: tujiLocalized("收藏的合集")
        case .lookupPrompt: tujiLocalized("查單字")
        case let .lookup(query): tujiLocalized("查「\(query)」這個詞")
        case .askModel: tujiLocalized("問 AI")
        }
    }
}
