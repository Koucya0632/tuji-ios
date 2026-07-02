import Foundation

@MainActor
protocol CatalogRepository {
    func loadCategories(lang: String) async throws -> CategoriesResponse
    func loadWords(lang: String, learning: String) async throws -> WordsListResponse
    func loadCustomWords() async throws -> WordsListResponse
    func search(_ query: String) async throws -> SearchResponse
    func word(id: String, lang: String, learning: String) async throws -> Word
}

@MainActor
struct LiveCatalogRepository: CatalogRepository {
    static let shared = LiveCatalogRepository()

    private let api: APIClient

    init(api: APIClient = .shared) {
        self.api = api
    }

    func loadCategories(lang: String) async throws -> CategoriesResponse {
        try await self.api.get(.categories(lang: lang))
    }

    func loadWords(lang: String, learning: String) async throws -> WordsListResponse {
        try await self.api.get(.words(lang: lang, learning: learning))
    }

    func loadCustomWords() async throws -> WordsListResponse {
        try await self.api.get(.usersCustomWords)
    }

    func search(_ query: String) async throws -> SearchResponse {
        try await self.api.get(.search(q: query))
    }

    func word(id: String, lang: String, learning: String) async throws -> Word {
        try await self.api.get(.word(id: id, lang: lang, learning: learning))
    }
}

struct SearchResponse: Decodable {
    let results: [CardWord]
    let query: String?
    let limit: Int?
}
