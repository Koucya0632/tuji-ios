// Word data models matching the backend payloads.
//
// `CardWord` is the lite shape returned by GET /api/words — used by list
// views (Cards / Today's themes / Search results / Favorites).
//
// The full `Word` shape (with definitions / examples / relations /
// etymology / forms) comes from GET /api/words/{id} and is loaded
// on-demand by WordDetailView; defined separately when that view ships.

import Foundation

struct CardWord: Codable, Identifiable, Hashable {
    let id: String
    let word: String
    let chinese: String
    let imageUrl: String
    let category: String
    let pronunciation: String

    var imageURL: URL? {
        URL(string: imageUrl)
    }
}

struct WordsListResponse: Decodable {
    let words: [CardWord]
    let total: Int
}

// Full per-word detail returned by GET /api/words/{id}. Most heavy fields
// (definitions / examples / relations / etymology / forms / collocations)
// are optional — the backend trims them when there's nothing to send, so
// every section in WordDetailView renders conditionally.

struct Word: Codable, Identifiable, Hashable {
    let id: String
    let word: String
    let alsoKnownAs: [String]?
    let category: String
    let partOfSpeech: String?
    let pronunciation: String?
    let audioUrl: String?
    let imageUrl: String
    let cefrLevel: String?
    let status: String?

    /// Convenience: server primaries the first zh-Hant definition into
    /// `chinese` so list views can render without unwrapping the full
    /// definitions array.
    let chinese: String

    let definitions: [WordDefinition]?
    let examples: [WordExample]?
    let relations: [WordRelation]?
    let collocations: [String]?
    let note: String?
    let etymology: String?
    let forms: [WordForm]?
    let chineseDefinition: String?
    let tags: [String]?

    var imageURL: URL? {
        URL(string: imageUrl)
    }
}

struct WordDefinition: Codable, Hashable {
    let language: String
    let definition: String
    let cefrLevel: String?
    let sortOrder: Int?
}

struct WordExample: Codable, Hashable {
    let en: String
    let zh: String?
    let translations: [String: String]?
    let cefrLevel: String?
    let sortOrder: Int?
}

struct WordRelation: Codable, Hashable {
    let wordId: String
    let type: String
    let note: String?
}

struct WordForm: Codable, Hashable {
    let label: String
    let value: String
}
