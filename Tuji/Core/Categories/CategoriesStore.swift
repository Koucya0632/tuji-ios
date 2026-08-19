// In-memory cache of the localized category list. Loaded once on app
// launch alongside WordsStore. Every screen that needs to render a
// category badge / hero (CardsListView chips, CategoryView, Today
// themes) reads from here without re-fetching.

import Foundation
import Observation
import OSLog

@MainActor
@Observable
final class CategoriesStore {
    static let shared = CategoriesStore()

    private(set) var categories: [TujiCategory] = []
    private(set) var loading: Bool = false
    private(set) var lastError: Error?

    /// True once the first load attempt has finished (success *or* failure).
    /// Used by the splash gate so a failed load doesn't trap us on Splash.
    private(set) var loaded: Bool = false

    private let repository: CatalogRepository
    private let log = Logger(subsystem: "app.tuji.ios", category: "categories")

    @ObservationIgnored private var loadedContext: CatalogContext?
    /// Coalescing, the publish guard and the loading flag — see `LoadFlights`,
    /// which 單字 and 設定 hold too.
    @ObservationIgnored private let flights = LoadFlights<CatalogContext>()
    @ObservationIgnored private var categoryCache: [String: [TujiCategory]] = [:]
    @ObservationIgnored private var categoryInFlight: [String: CategoryFlight] = [:]

    private struct CategoryFlight {
        let id: UUID
        let task: Task<Result<[TujiCategory], Error>, Never>
    }

    init(repository: CatalogRepository = LiveCatalogRepository.shared) {
        self.repository = repository
    }

    func loadIfNeeded() async {
        await self.loadIfNeeded(for: CatalogContext.current())
    }

    func loadIfNeeded(for context: CatalogContext) async {
        guard self.loadedContext != context || !self.loaded || self.lastError != nil else { return }
        await self.load(for: context, reuseCached: true)
    }

    func reload() async {
        await self.reload(for: CatalogContext.current())
    }

    /// Coalesces identical requests and prevents a slower, obsolete context
    /// from replacing the newest localized category snapshot.
    func reload(for context: CatalogContext) async {
        await self.load(for: context, reuseCached: false)
    }

    private func load(for context: CatalogContext, reuseCached: Bool) async {
        self.loading = true
        self.lastError = nil
        await self.flights.run(
            context,
            fetch: {
                await self.fetchCategories(
                    language: context.contentLanguageCode,
                    reuseCached: reuseCached
                )
            },
            publish: { result, _ in self.publish(result, for: context) }
        )
        self.refreshLoadingState()
    }

    /// Runs only for a result that is still the one being waited for — the
    /// staleness guard lives in `LoadFlights`.
    private func publish(_ result: Result<[TujiCategory], Error>, for context: CatalogContext) {
        self.loadedContext = context
        self.loaded = true
        switch result {
        case let .success(categories):
            self.categories = categories
            self.log.info("loaded \(categories.count, privacy: .public) categories")
        case let .failure(error):
            // Keep the last good categories visible while exposing retry state.
            self.lastError = error
            self.log.error("categories load failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func fetchCategories(
        language: String,
        reuseCached: Bool
    ) async
        -> Result<[TujiCategory], Error>
    {
        if reuseCached, let cached = self.categoryCache[language] {
            return .success(cached)
        }
        if let flight = self.categoryInFlight[language] {
            return await flight.task.value
        }

        let flightID = UUID()
        let repository = self.repository
        let task = Task { () -> Result<[TujiCategory], Error> in
            do {
                let response = try await repository.loadCategories(lang: language)
                return .success(response.categories)
            } catch {
                return .failure(error)
            }
        }
        self.categoryInFlight[language] = CategoryFlight(id: flightID, task: task)
        let result = await task.value
        let flightIsCurrent = self.categoryInFlight[language]?.id == flightID
        if flightIsCurrent {
            self.categoryInFlight[language] = nil
        }
        if flightIsCurrent, case let .success(categories) = result {
            self.categoryCache[language] = categories
        }
        return result
    }

    private func refreshLoadingState() {
        self.loading = self.flights.isLoading
    }

    func invalidate() {
        self.loadedContext = nil
        self.flights.reset()
        for flight in self.categoryInFlight.values {
            flight.task.cancel()
        }
        self.categoryInFlight.removeAll()
        self.categoryCache.removeAll()
        self.categories = []
        self.loading = false
        self.loaded = false
    }

    func find(id: String) -> TujiCategory? {
        self.categories.first { $0.id == id }
    }
}
