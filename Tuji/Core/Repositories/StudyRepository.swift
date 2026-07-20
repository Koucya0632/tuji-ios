import Foundation
import OSLog

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
                categories: categories,
                lang: SettingsStore.shared.current.uiLang
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
        // Unlike analytics fire-and-forget, a dropped SRS write is user-visible
        // damage: the word stays 未學 and the daily goal miscounts. Retry with
        // short backoff, then park in the durable outbox for a later replay.
        for attempt in 0..<3 {
            do {
                let _: StudyAnswerResponse = try await self.api.post(.studyAnswer, body: payload)
                return
            } catch {
                let log = Logger(subsystem: "app.tuji.ios", category: "study-repo")
                log.warning(
                    "answer write attempt \(attempt + 1, privacy: .public) failed: \(error.localizedDescription, privacy: .public)"
                )
                if attempt < 2 {
                    try? await Task.sleep(for: .milliseconds(400 << attempt))
                }
            }
        }
        StudyAnswerOutbox.shared.add(payload)
    }

    func submitReport(_ payload: StudyReportPayload) async throws {
        let _: Empty = try await self.api.post(.studyReports, body: payload)
    }
}
