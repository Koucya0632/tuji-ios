import Foundation

/// The four reads and one write behind 打卡. Its own protocol rather than more
/// requirements on `ProgressRepository`, so the fakes of that one don't grow.
@MainActor
protocol CheckInRepository {
    func loadCatalog() async throws -> CreditCatalog
    func loadWallet() async throws -> CreditWallet
    /// Claims today's check-in points; returns the wallet after the claim.
    func checkIn() async throws -> CreditWallet
    /// `month` is YYYY-MM; nil is the server's current month.
    func loadCalendar(month: String?) async throws -> StudyCalendarMonth
}

@MainActor
struct LiveCheckInRepository: CheckInRepository {
    private let api: APIClient
    /// Read at call time: the calendar is per learning direction, like the
    /// streak it sits beside (see `LiveProgressRepository`).
    private let settings: LanguageContext

    init(api: APIClient = .shared, settings: LanguageContext = SettingsStore.shared) {
        self.api = api
        self.settings = settings
    }

    func loadCatalog() async throws -> CreditCatalog {
        try await self.api.get(.creditCatalog)
    }

    func loadWallet() async throws -> CreditWallet {
        try await self.api.get(.creditWallet)
    }

    func checkIn() async throws -> CreditWallet {
        struct Claim: Decodable { let wallet: CreditWallet }
        let claim: Claim = try await self.api.post(.creditCheckIn, body: Empty())
        return claim.wallet
    }

    func loadCalendar(month: String?) async throws -> StudyCalendarMonth {
        try await self.api.get(.usersStudyCalendar(month: month, learning: self.settings.learningDirection.rawValue))
    }
}
