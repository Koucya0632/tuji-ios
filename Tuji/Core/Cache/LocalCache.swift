// Authoritative store for favorites / learned / recent-searches when not
// signed in, and an offline cache layer when signed in.
//
// Persistence: UserDefaults (encrypted on iOS, good enough for these
// non-secret list of ids).
//
// Pattern matches the web app's localStorage approach (ARCHITECTURE.md §9):
//   - Mutations write locally first, then fire-and-forget to the server
//   - Sign-in triggers a one-time sync that uploads the local snapshot to
//     /api/users/sync and merges the response back in (union semantics)

import Foundation
import Observation

@MainActor
@Observable
final class LocalCache {
    static let shared = LocalCache()

    private(set) var favoriteIds: Set<String>
    private(set) var learnedIds: Set<String>
    private(set) var recentSearches: [String]
    let sessionId: String

    private let favsKey = "tuji.cache.favorites"
    private let learnedKey = "tuji.cache.learned"
    private let recentKey = "tuji.cache.recentSearches"
    private let sessionKey = "tuji.cache.sessionId"
    private let maxRecent = 10

    private init() {
        let d = UserDefaults.standard
        favoriteIds = Set((d.array(forKey: favsKey) as? [String]) ?? [])
        learnedIds = Set((d.array(forKey: learnedKey) as? [String]) ?? [])
        recentSearches = (d.array(forKey: recentKey) as? [String]) ?? []
        if let existing = d.string(forKey: sessionKey) {
            sessionId = existing
        } else {
            let new = UUID().uuidString
            d.set(new, forKey: sessionKey)
            sessionId = new
        }
    }

    // MARK: - Favorites / Learned

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

    func markLearned(_ id: String) {
        guard !learnedIds.contains(id) else { return }
        learnedIds.insert(id)
        persistLearned()
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
        UserDefaults.standard.set(recentSearches, forKey: recentKey)
    }

    func clearRecentSearches() {
        recentSearches = []
        UserDefaults.standard.set(recentSearches, forKey: recentKey)
    }

    // MARK: - Sync

    /// Server-side data merges INTO local — union semantics so the user
    /// never loses anything from the device.
    func mergeFromServer(favorites: [String], learned: [String]) {
        favoriteIds.formUnion(favorites)
        learnedIds.formUnion(learned)
        persistFavorites()
        persistLearned()
    }

    /// Snapshot uploaded to POST /api/users/sync at sign-in time.
    var syncSnapshot: SyncPayload {
        SyncPayload(
            favorites: Array(favoriteIds).sorted(),
            learned: Array(learnedIds).sorted()
        )
    }

    // MARK: - Private

    private func persistFavorites() {
        UserDefaults.standard.set(Array(favoriteIds), forKey: favsKey)
    }

    private func persistLearned() {
        UserDefaults.standard.set(Array(learnedIds), forKey: learnedKey)
    }
}

struct SyncPayload: Codable {
    let favorites: [String]
    let learned: [String]
}
