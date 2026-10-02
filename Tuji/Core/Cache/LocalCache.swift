// The device's copy of the account's bookmarks, plus recent searches.
//
// Persistence: UserDefaults (encrypted on iOS, good enough for these
// non-secret list of ids).
//
// Bookmark mutations write locally first, then fire-and-forget to the server;
// the server's list is merged back in after sign-in (union semantics).

import Foundation
import Observation

@MainActor
@Observable
final class LocalCache {
    static let shared = LocalCache()

    private(set) var favoriteIds: Set<String>
    private(set) var recentSearches: [String]
    let sessionId: String

    private let defaults: UserDefaults
    private let favsKey = "tuji.cache.favorites"
    private let recentKey = "tuji.cache.recentSearches"
    private let sessionKey = "tuji.cache.sessionId"
    private let maxRecent = 10

    /// Internal so a test can stand one up over its own defaults — the account
    /// boundary below is the part worth asserting, and a `private init` over
    /// `.standard` made it unreachable.
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let d = defaults
        favoriteIds = Set((d.array(forKey: favsKey) as? [String]) ?? [])
        recentSearches = (d.array(forKey: recentKey) as? [String]) ?? []
        if let existing = d.string(forKey: sessionKey) {
            sessionId = existing
        } else {
            let new = UUID().uuidString
            d.set(new, forKey: sessionKey)
            sessionId = new
        }
    }

    // MARK: - Favorites

    func isFavorite(_ id: String) -> Bool {
        favoriteIds.contains(id)
    }

    func toggleFavorite(_ id: String) {
        if favoriteIds.contains(id) {
            favoriteIds.remove(id)
        } else {
            favoriteIds.insert(id)
        }
        persistFavorites()
    }

    // MARK: - Recent searches

    func pushRecentSearch(_ q: String) {
        let trimmed = q.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        recentSearches.removeAll { $0 == trimmed }
        recentSearches.insert(trimmed, at: 0)
        if recentSearches.count > maxRecent {
            recentSearches = Array(recentSearches.prefix(maxRecent))
        }
        self.defaults.set(recentSearches, forKey: recentKey)
    }

    func clearRecentSearches() {
        recentSearches = []
        self.defaults.set(recentSearches, forKey: recentKey)
    }

    // MARK: - Account boundary

    /// The account's server bookmarks, merged in after sign-in. Union: nothing
    /// here may drop one the user can see.
    ///
    /// Before this existed the server's list was decoded and ignored, so a
    /// fresh install showed no bookmarks for an account that had them, and the
    /// device list was the only one that ever looked right.
    func mergeServerFavorites(_ favorites: [String]) {
        let merged = self.favoriteIds.union(favorites)
        guard merged != self.favoriteIds else { return }
        self.favoriteIds = merged
        persistFavorites()
    }

    /// Sign-out. The bookmarks here were this account's, and keeping them
    /// handed one person's 書籤 to the next. Recent searches stay: they are
    /// this device's history, not an account's.
    func reset() {
        self.favoriteIds = []
        persistFavorites()
    }

    // MARK: - Private

    private func persistFavorites() {
        self.defaults.set(Array(favoriteIds), forKey: favsKey)
    }
}
