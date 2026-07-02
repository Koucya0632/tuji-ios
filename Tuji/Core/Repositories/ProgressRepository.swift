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

    init(api: APIClient = .shared) {
        self.api = api
    }

    func loadProgress() async throws -> ProgressResponse {
        try await self.api.get(.usersProgress)
    }

    func clearProgress() async throws {
        try await self.api.delete(.usersProgress)
    }

    func loadMastery() async throws -> MasteryListResponse {
        try await self.api.get(.usersMastery)
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
