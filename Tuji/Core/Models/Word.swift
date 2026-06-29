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
    let reading: String?
    let targetLanguage: String?
    /// Pre-generated pronunciation clips keyed by locale ("en-US" / "en-GB" /
    /// "ja-JP"). The server only sends the locales relevant to the active
    /// learning direction; nil when no audio has been generated.
    let audioUrls: [String: String]?
    /// Full per-word detail, present only for 自制圖鑑 (custom) words —
    /// /api/users/custom-words embeds it so WordDetailView can render without a
    /// second /api/atlas/items/{id}/detail round-trip. nil for public words.
    let detail: Word?

    init(
        id: String,
        word: String,
        chinese: String,
        imageUrl: String,
        category: String,
        pronunciation: String,
        reading: String? = nil,
        targetLanguage: String? = nil,
        audioUrls: [String: String]? = nil,
        detail: Word? = nil
    ) {
        self.id = id
        self.word = word
        self.chinese = chinese
        self.imageUrl = imageUrl
        self.category = category
        self.pronunciation = pronunciation
        self.reading = reading
        self.targetLanguage = targetLanguage
        self.audioUrls = audioUrls
        self.detail = detail
    }

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
    let reading: String?
    let targetLanguage: String?
    let audioUrl: String?
    /// Per-locale pronunciation clips ("en-US" / "en-GB" / "ja-JP"); superset
    /// of `audioUrl`, which mirrors the en-US clip.
    let audioUrls: [String: String]?
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
    /// zh-Hant translations parallel to `collocations`. Server overlays
    /// these from word_localized_texts(field='collocations',
    /// language='zh-Hant'); ja currently has none so this may be nil for
    /// ja users. iOS treats it as optional and falls back to en-only.
    let collocationsZh: [String]?
    let note: String?
    let etymology: String?
    let forms: [WordForm]?
    let chineseDefinition: String?
    /// Definition in the active learning target language (`en` or `ja`).
    let targetDefinition: String?
    /// Convenience: first en-language definition prefilled by the server
    /// (the `definitions` array itself is lang-filtered so the en row
    /// gets dropped when UI lang is zh-Hant — see lib/word-localize.ts).
    let englishDefinition: String?
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
    /// Sentence in the active learning target language. Japanese detail
    /// payloads omit examples that do not have this value.
    let target: String?
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
