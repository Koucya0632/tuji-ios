import Foundation

@MainActor
protocol ProgressRepository {
    func loadProgress() async throws -> ProgressResponse
    func clearProgress() async throws
    func loadMastery() async throws -> MasteryListResponse
    func loadTopWords(type: String, limit: Int) async throws -> TopWordsResponse
    func toggleFavorite(wordId: String, isFavorite: Bool) async
}

@MainActor
struct LiveProgressRepository: ProgressRepository {
    static let shared = LiveProgressRepository()

    private let api: APIClient
    /// 連勝、完成度 and 熟練度 all live in a per-direction namespace, and both
    /// reads are re-issued the moment 學習語言 changes — before the debounced
    /// settings POST has told the server. So the repository states the scope
    /// rather than letting the server infer it, the same way
    /// `LiveCatalogRepository.search` does. Read live at call time, per ADR-0001.
    private let settings: LanguageContext

    init(api: APIClient = .shared, settings: LanguageContext = SettingsStore.shared) {
        self.api = api
        self.settings = settings
    }

    private var learning: String {
        self.settings.learningDirection.rawValue
    }

    func loadProgress() async throws -> ProgressResponse {
        try await self.api.get(.usersProgress(learning: self.learning))
    }

    /// Clears every direction, so it names none.
    func clearProgress() async throws {
        try await self.api.delete(.usersProgressClear)
    }

    func loadMastery() async throws -> MasteryListResponse {
        try await self.api.get(.usersMastery(learning: self.learning))
    }

    func loadTopWords(type: String, limit: Int) async throws -> TopWordsResponse {
        try await self.api.get(.usersTopWords(type: type, limit: limit))
    }

    func toggleFavorite(wordId: String, isFavorite: Bool) async {
        await self.api.fireAndForget(
            .usersFavorites,
            body: FavoritePayload(wordId: wordId, op: isFavorite ? "add" : "remove")
        )
    }
}

/// nonisolated so Encodable conformance escapes MainActor isolation;
/// needed because APIClient.fireAndForget requires Body: Sendable.
// swiftformat:disable:next redundantSendable
private nonisolated struct FavoritePayload: Encodable, Sendable {
    let wordId: String
    let op: String
}
