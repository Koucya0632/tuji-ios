import Foundation

@MainActor
protocol CatalogRepository {
    func loadCategories(lang: String) async throws -> CategoriesResponse
    func loadWords(lang: String, learning: String) async throws -> WordsListResponse
    func loadCustomWords(lang: String, learning: String) async throws -> WordsListResponse
    func loadSavedWords(lang: String, learning: String) async throws -> WordsListResponse
    func search(_ query: String) async throws -> SearchResponse
    func word(id: String, lang: String, learning: String) async throws -> Word
}

@MainActor
struct LiveCatalogRepository: CatalogRepository {
    static let shared = LiveCatalogRepository()

    private let api: APIClient
    /// Only `search` needs this: the other calls are driven by a `CatalogContext`
    /// the caller already assembled. Read live at call time, per ADR-0001.
    private let settings: LanguageContext

    init(api: APIClient = .shared, settings: LanguageContext = SettingsStore.shared) {
        self.api = api
        self.settings = settings
    }

    func loadCategories(lang: String) async throws -> CategoriesResponse {
        try await self.api.get(.categories(lang: lang))
    }

    func loadWords(lang: String, learning: String) async throws -> WordsListResponse {
        try await self.api.get(.words(lang: lang, learning: learning))
    }

    func loadCustomWords(lang: String, learning: String) async throws -> WordsListResponse {
        try await self.api.get(.usersCustomWords(lang: lang, learning: learning))
    }

    /// Saved 公開圖鑑 items, already shaped as words with `category: "community"`
    /// so they merge into the same store and light up the 物見 theme.
    func loadSavedWords(lang: String, learning: String) async throws -> WordsListResponse {
        try await self.api.get(.usersSavedWords(lang: lang, learning: learning))
    }

    /// Scopes itself rather than making `SearchVM` remember to: search results
    /// differ by learning direction, and the endpoint is publicly cached, so the
    /// direction belongs to the request's identity. The repository is where the
    /// other language-scoped calls resolve it too.
    func search(_ query: String) async throws -> SearchResponse {
        try await self.api.get(.search(
            q: query,
            lang: self.settings.uiLang,
            learning: self.settings.learningDirection.rawValue
        ))
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
