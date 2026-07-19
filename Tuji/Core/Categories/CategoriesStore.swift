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

    private init(repository: CatalogRepository = LiveCatalogRepository.shared) {
        self.repository = repository
    }

    func loadIfNeeded() async {
        guard self.categories.isEmpty else { return }
        await self.reload()
    }

    func reload() async {
        self.loading = true
        self.lastError = nil
        defer {
            self.loading = false
            self.loaded = true
        }
        do {
            let resp = try await self.repository.loadCategories(
                lang: SettingsStore.shared.current.uiLanguage.contentLanguageCode
            )
            self.categories = resp.categories
            self.log.info("loaded \(resp.categories.count, privacy: .public) categories")
        } catch {
            self.lastError = error
            self.log.error("categories load failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    func invalidate() {
        self.categories = []
        self.loaded = false
    }

    func find(id: String) -> TujiCategory? {
        self.categories.first { $0.id == id }
    }
}
