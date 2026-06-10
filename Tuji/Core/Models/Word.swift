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
