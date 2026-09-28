import Foundation

/// 個人詞表 over the wire. Every read and write is scoped to the live learning
/// direction, like the other direction-owned reads: the server keeps English
/// and Japanese lists apart.
@MainActor
protocol WordListRepository {
    /// `containing` asks the server to mark which lists already hold that word.
    func lists(containing wordId: String?) async throws -> WordListsResponse
    func detail(id: String) async throws -> WordListDetailResponse
    func create(name: String) async throws -> WordList
    func rename(id: String, name: String) async throws
    func delete(id: String) async throws
    func reorder(ids: [String]) async throws
    func setWord(_ wordId: String, inList listId: String, present: Bool) async throws
    func queue(listId: String, mode: StudyMode, limit: Int) async throws -> StudyQueueResponse
}

@MainActor
struct LiveWordListRepository: WordListRepository {
    static let shared = LiveWordListRepository()

    private let api: APIClient
    private let settings: LanguageContext

    init(api: APIClient = .shared, settings: LanguageContext = SettingsStore.shared) {
        self.api = api
        self.settings = settings
    }

    private var learning: String {
        self.settings.learningDirection.rawValue
    }

    func lists(containing wordId: String?) async throws -> WordListsResponse {
        try await self.api.get(.usersWordLists(learning: self.learning, word: wordId))
    }

    func detail(id: String) async throws -> WordListDetailResponse {
        try await self.api.get(.usersWordList(id: id))
    }

    func create(name: String) async throws -> WordList {
        let response: WordListCreateResponse = try await self.api.post(
            .usersWordLists(learning: self.learning, word: nil),
            body: WordListNamePayload(name: name)
        )
        return response.list
    }

    func rename(id: String, name: String) async throws {
        try await self.api.patch(
            .usersWordList(id: id),
            body: WordListNamePayload(name: name),
            as: WordListOkResponse.self
        )
    }

    func delete(id: String) async throws {
        try await self.api.delete(.usersWordList(id: id))
    }

    func reorder(ids: [String]) async throws {
        try await self.api.post(
            .usersWordListOrder(learning: self.learning),
            body: WordListOrderPayload(ids: ids),
            as: WordListOkResponse.self
        )
    }

    func setWord(_ wordId: String, inList listId: String, present: Bool) async throws {
        try await self.api.post(
            .usersWordListWords(id: listId),
            body: WordListWordPayload(wordId: wordId, add: present),
            as: WordListOkResponse.self
        )
    }

    func queue(listId: String, mode: StudyMode, limit: Int) async throws -> StudyQueueResponse {
        try await self.api.get(
            .studyWordListQueue(
                listId: listId,
                mode: mode.asPath,
                limit: max(1, limit),
                lang: self.settings.uiLang,
                learning: self.learning
            )
        )
    }
}
