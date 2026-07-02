import Foundation

@MainActor
protocol StudyRepository {
    func loadQueue(mode: StudyMode, limit: Int, newCount: Int, categories: [String]) async throws -> StudyQueueResponse
    func loadStats() async throws -> StudyStatsResponse
    func submitAnswer(_ payload: StudyAnswerPayload) async throws -> StudyAnswerResponse
    func submitAnswerBestEffort(_ payload: StudyAnswerPayload) async
    func submitReport(_ payload: StudyReportPayload) async throws
}

@MainActor
struct LiveStudyRepository: StudyRepository {
    static let shared = LiveStudyRepository()

    private let api: APIClient

    init(api: APIClient = .shared) {
        self.api = api
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
                categories: categories
            )
        )
    }

    func loadStats() async throws -> StudyStatsResponse {
        try await self.api.get(.studyStats)
    }

    func submitAnswer(_ payload: StudyAnswerPayload) async throws -> StudyAnswerResponse {
        try await self.api.post(.studyAnswer, body: payload)
    }

    func submitAnswerBestEffort(_ payload: StudyAnswerPayload) async {
        await self.api.fireAndForget(.studyAnswer, body: payload)
    }

    func submitReport(_ payload: StudyReportPayload) async throws {
        let _: Empty = try await self.api.post(.studyReports, body: payload)
    }
}
