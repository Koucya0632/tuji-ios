import Foundation

@MainActor
protocol WordNoteRepository {
    func notes() async throws -> WordNotesResponse
    func save(wordId: String, body: String) async throws -> WordNote
    func delete(wordId: String) async throws
}

@MainActor
struct LiveWordNoteRepository: WordNoteRepository {
    static let shared = LiveWordNoteRepository()

    private let api: APIClient

    init(api: APIClient = .shared) {
        self.api = api
    }

    func notes() async throws -> WordNotesResponse {
        try await self.api.get(.usersWordNotes)
    }

    func save(wordId: String, body: String) async throws -> WordNote {
        let response: WordNoteSaveResponse = try await self.api.post(
            .usersWordNote(wordId: wordId),
            body: WordNotePayload(body: body)
        )
        return response.note
    }

    func delete(wordId: String) async throws {
        try await self.api.delete(.usersWordNote(wordId: wordId))
    }
}
