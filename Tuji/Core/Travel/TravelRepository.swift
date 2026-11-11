import Foundation

@MainActor
protocol TravelRepository {
    func destinations(lang: String, learning: String) async throws -> TravelResponse
    func queue(spotId: String, mode: StudyMode, limit: Int) async throws -> StudyQueueResponse
}

@MainActor
struct LiveTravelRepository: TravelRepository {
    static let shared = LiveTravelRepository()

    private let api: APIClient
    private let settings: LanguageContext

    init(api: APIClient = .shared, settings: LanguageContext = SettingsStore.shared) {
        self.api = api
        self.settings = settings
    }

    func destinations(lang: String, learning: String) async throws -> TravelResponse {
        try await self.api.get(.travel(lang: lang, learning: learning))
    }

    func queue(spotId: String, mode: StudyMode, limit: Int) async throws -> StudyQueueResponse {
        try await self.api.get(
            .studySpotQueue(
                spotId: spotId,
                mode: mode.asPath,
                limit: max(1, limit),
                lang: self.settings.uiLang,
                learning: self.settings.learningDirection.rawValue
            )
        )
    }
}
