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

    @ObservationIgnored private var latestRequestedContext: CatalogContext?
    @ObservationIgnored private var loadedContext: CatalogContext?
    @ObservationIgnored private var inFlight: [CatalogContext: LoadFlight] = [:]
    @ObservationIgnored private var categoryCache: [String: [TujiCategory]] = [:]
    @ObservationIgnored private var categoryInFlight: [String: CategoryFlight] = [:]

    private struct LoadFlight {
        let id: UUID
        let task: Task<Void, Never>
    }

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
        self.latestRequestedContext = context
        self.loading = true
        self.lastError = nil

        if let flight = self.inFlight[context] {
            await flight.task.value
            return
        }

        let flightID = UUID()
        let task = Task { [weak self] in
            guard let self else { return }
            await self.performReload(
                for: context,
                flightID: flightID,
                reuseCached: reuseCached
            )
        }
        self.inFlight[context] = LoadFlight(id: flightID, task: task)
        await task.value

        if self.inFlight[context]?.id == flightID {
            self.inFlight[context] = nil
        }
        self.refreshLoadingState()
    }

    private func performReload(
        for context: CatalogContext,
        flightID: UUID,
        reuseCached: Bool
    ) async {
        let result = await self.fetchCategories(
            language: context.contentLanguageCode,
            reuseCached: reuseCached
        )

        guard self.latestRequestedContext == context,
              self.inFlight[context]?.id == flightID
        else { return }
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
        guard let latestRequestedContext else {
            self.loading = false
            return
        }
        self.loading = self.inFlight[latestRequestedContext] != nil
    }

    func invalidate() {
        self.latestRequestedContext = nil
        self.loadedContext = nil
        for flight in self.inFlight.values {
            flight.task.cancel()
        }
        for flight in self.categoryInFlight.values {
            flight.task.cancel()
        }
        self.inFlight.removeAll()
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
