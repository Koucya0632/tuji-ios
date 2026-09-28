// 個人詞表 wire models — /api/users/word-lists (tuji-web lib/word-lists).
//
// The server decides everything a screen needs to gate on: whether the feature
// exists for this account at all (`available`, false under membership policy
// v1), whether a list is `locked` (past the cap after a downgrade), and what
// the account may do with one list (`canEdit`, `canStudy`). The app only draws
// those answers.

import Foundation

struct WordList: Decodable, Identifiable, Hashable {
    let id: String
    let name: String
    let targetLanguage: String
    let position: Int
    let wordCount: Int
    /// Past the list cap after a downgrade: readable and deletable only.
    let locked: Bool
    /// Present only on a listing asked about one word (the 加入詞表 sheet).
    let containsWord: Bool?
}

struct WordListLimits: Decodable, Hashable {
    let lists: Int
    let words: Int
}

struct WordListsResponse: Decodable {
    let available: Bool
    let tier: String?
    let canCreate: Bool?
    let limits: WordListLimits?
    let lists: [WordList]
}

struct WordListStats: Decodable, Hashable {
    let total: Int
    let seen: Int
    let due: Int

    /// Never studied, in this list's deck.
    var unseen: Int {
        max(0, self.total - self.seen)
    }
}

struct WordListDetailResponse: Decodable {
    let list: WordList
    let wordIds: [String]
    let stats: WordListStats
    let canEdit: Bool
    let canStudy: Bool
    let wordLimit: Int
}

struct WordListCreateResponse: Decodable {
    let list: WordList
}

struct WordListNamePayload: Encodable {
    let name: String
}

struct WordListWordPayload: Encodable {
    let wordId: String
    let add: Bool
}

struct WordListOrderPayload: Encodable {
    let ids: [String]
}

struct WordListOkResponse: Decodable {
    let ok: Bool?
}
