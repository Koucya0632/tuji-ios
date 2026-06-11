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

    private let log = Logger(subsystem: "app.tuji.ios", category: "categories")

    private init() {}

    func loadIfNeeded() async {
        guard self.categories.isEmpty else { return }
        await self.reload()
    }

    func reload() async {
        self.loading = true
        self.lastError = nil
        defer { self.loading = false }
        do {
            let resp: CategoriesResponse = try await APIClient.shared.get(.categories)
            self.categories = resp.categories
            self.log.info("loaded \(resp.categories.count, privacy: .public) categories")
        } catch {
            self.lastError = error
            self.log.error("categories load failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    func find(id: String) -> TujiCategory? {
        self.categories.first { $0.id == id }
    }
}
