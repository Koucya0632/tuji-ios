// Single source of truth for the entire word dictionary client-side.
//
// Calls GET /api/words once at app launch, keeps the array in memory,
// and exposes filter/lookup helpers so every screen (Cards, Today,
// Search, Favorites, etc.) reads the same data without re-fetching.
//
// The backend response is next-cache wrapped, so a fresh load is cheap;
// we still cache locally to avoid the network round trip after the
// first call. Failure leaves `words` empty + sets `lastError`; the UI
// can offer a retry via `reload()`.

import Foundation
import Observation
import OSLog

@MainActor
@Observable
final class WordsStore {
    static let shared = WordsStore()

    private(set) var words: [CardWord] = []
    private(set) var loading: Bool = false
    private(set) var lastError: Error?

    /// True once the first load attempt has finished (success *or* failure).
    /// Used by the splash gate so a failed load doesn't trap us on Splash.
    private(set) var loaded: Bool = false

    private let repository: CatalogRepository
    private let log = Logger(subsystem: "app.tuji.ios", category: "words")

    private init(repository: CatalogRepository = LiveCatalogRepository.shared) {
        self.repository = repository
    }

    /// Returns immediately if we already have words. Triggers a fresh
    /// network load otherwise.
    func loadIfNeeded() async {
        guard self.words.isEmpty else { return }
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
            let settings = SettingsStore.shared.current
            let resp = try await self.repository.loadWords(
                lang: settings.uiLang,
                learning: settings.learningDirection.rawValue
            )
            var merged = resp.words
            do {
                let custom = try await self.repository.loadCustomWords()
                merged = Self.merge(publicWords: resp.words, customWords: custom.words)
            } catch {
                self.log.info("custom words skipped: \(error.localizedDescription, privacy: .public)")
            }
            self.words = merged
            self.log.info("loaded \(merged.count, privacy: .public) words")
        } catch {
            self.lastError = error
            self.log.error("words load failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    func invalidate() {
        self.words = []
        self.loaded = false
    }

    // MARK: - Filters

    func byCategory(_ id: String?) -> [CardWord] {
        guard let id else { return self.words }
        return self.words.filter { $0.category == id }
    }

    func byIds(_ ids: Set<String>) -> [CardWord] {
        self.words.filter { ids.contains($0.id) }
    }

    func find(id: String) -> CardWord? {
        self.words.first { $0.id == id }
    }

    /// All unique category ids represented in the current dataset.
    var categories: [String] {
        Array(Set(self.words.map(\.category))).sorted()
    }

    private static func merge(publicWords: [CardWord], customWords: [CardWord]) -> [CardWord] {
        // Last-wins by id. Built with a loop rather than
        // Dictionary(uniqueKeysWithValues:), which traps fatally if the server
        // ever returns a duplicate id in the public list.
        var byId: [String: CardWord] = [:]
        for word in publicWords {
            byId[word.id] = word
        }
        for word in customWords {
            byId[word.id] = word
        }
        return Array(byId.values).sorted {
            if $0.category != $1.category { return $0.category < $1.category }
            return $0.word.localizedCaseInsensitiveCompare($1.word) == .orderedAscending
        }
    }
}
