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
    /// 主題組合, from the same response as `categories` — so a preset never
    /// names a theme this snapshot does not have.
    private(set) var presets: [TopicPreset] = []
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
    @ObservationIgnored private var categoryCache: [CategoryKey: CategoriesResponse] = [:]
    @ObservationIgnored private var categoryInFlight: [CategoryKey: CategoryFlight] = [:]

    private struct CategoryKey: Hashable {
        let language: String
        let learning: String

        init(_ context: CatalogContext) {
            self.language = context.contentLanguageCode
            self.learning = context.learningDirectionCode
        }
    }

    private struct CategoryFlight {
        let id: UUID
        let task: Task<Result<CategoriesResponse, Error>, Never>
    }

    init(repository: CatalogRepository = LiveCatalogRepository.shared) {
        self.repository = repository
    }

    func loadIfNeeded() async {
        await self.loadIfNeeded(for: CatalogContext.current())
    }

    func loadIfNeeded(for context: CatalogContext) async {
        guard self.loadedContext != context || !self.loaded || self.lastError != nil ||
            self.flights.latestRequested != context else { return }
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
        if let previous = self.loadedContext, CategoryKey(previous) != CategoryKey(context) {
            self.categories = []
            self.presets = []
        }
        self.loading = true
        self.lastError = nil
        await self.flights.run(
            context,
            fetch: {
                await self.fetchCategories(
                    key: CategoryKey(context),
                    reuseCached: reuseCached
                )
            },
            publish: { result, _ in self.publish(result, for: context) }
        )
        self.refreshLoadingState()
    }

    /// Runs only for a result that is still the one being waited for — the
    /// staleness guard lives in `LoadFlights`.
    private func publish(_ result: Result<CategoriesResponse, Error>, for context: CatalogContext) {
        self.loadedContext = context
        self.loaded = true
        switch result {
        case let .success(response):
            self.categories = response.categories
            self.presets = response.presets
            self.log.info("loaded \(response.categories.count, privacy: .public) categories")
        case let .failure(error):
            // Keep the last good categories visible while exposing retry state.
            self.lastError = error
            self.log.error("categories load failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func fetchCategories(
        key: CategoryKey,
        reuseCached: Bool
    ) async
        -> Result<CategoriesResponse, Error>
    {
        if reuseCached, let cached = self.categoryCache[key] {
            return .success(cached)
        }
        if let flight = self.categoryInFlight[key] {
            return await flight.task.value
        }

        let flightID = UUID()
        let repository = self.repository
        let task = Task { () -> Result<CategoriesResponse, Error> in
            do {
                return try await .success(repository.loadCategories(lang: key.language, learning: key.learning))
            } catch {
                return .failure(error)
            }
        }
        self.categoryInFlight[key] = CategoryFlight(id: flightID, task: task)
        let result = await task.value
        let flightIsCurrent = self.categoryInFlight[key]?.id == flightID
        if flightIsCurrent {
            self.categoryInFlight[key] = nil
        }
        if flightIsCurrent, case let .success(response) = result {
            self.categoryCache[key] = response
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
        self.presets = []
        self.loading = false
        self.loaded = false
    }

    func find(id: String) -> TujiCategory? {
        self.categories.first { $0.id == id }
    }
}
