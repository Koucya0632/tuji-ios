import Foundation

@MainActor
protocol StudyRepository {
    func loadQueue(mode: StudyMode, limit: Int, newCount: Int, categories: [String]) async throws -> StudyQueueResponse
    func loadStats() async throws -> StudyStatsResponse
    /// One raw POST /api/study/answer, no retries. Durable, retrying writes go
    /// through `DurableAnswerWriter`; the only other direct caller is the
    /// outbox replay (which must NOT re-park on failure).
    func submitAnswer(_ payload: StudyAnswerPayload) async throws -> StudyAnswerResponse
    func submitReport(_ payload: StudyReportPayload) async throws
}

@MainActor
struct LiveStudyRepository: StudyRepository {
    static let shared = LiveStudyRepository()

    private let api: APIClient
    private let settings: LanguageContext

    init(api: APIClient = .shared, settings: LanguageContext = SettingsStore.shared) {
        self.api = api
        self.settings = settings
    }

    func loadQueue(
        mode: StudyMode,
        limit: Int,
        newCount: Int,
        categories: [String]
    ) async throws
        -> StudyQueueResponse
    {
        try await self.api.get(
            .studyQueue(
                mode: mode.asPath,
                limit: max(1, limit),
                new: newCount,
                categories: categories,
                lang: self.settings.uiLang,
                learning: self.settings.learningDirection.rawValue
            )
        )
    }

    func loadStats() async throws -> StudyStatsResponse {
        try await self.api.get(.studyStats(learning: self.settings.learningDirection.rawValue))
    }

    func submitAnswer(_ payload: StudyAnswerPayload) async throws -> StudyAnswerResponse {
        try await self.api.post(.studyAnswer, body: payload)
    }

    func submitReport(_ payload: StudyReportPayload) async throws {
        let _: Empty = try await self.api.post(.studyReports, body: payload)
    }
}
