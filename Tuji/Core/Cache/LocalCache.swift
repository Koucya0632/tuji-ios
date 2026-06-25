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
    private var learnedByLanguage: [String: Set<String>]
    private(set) var recentSearches: [String]
    let sessionId: String

    private let favsKey = "tuji.cache.favorites"
    private let learnedKey = "tuji.cache.learned"
    private let learnedEnKey = "tuji.cache.learned.en"
    private let learnedJaKey = "tuji.cache.learned.ja"
    private let recentKey = "tuji.cache.recentSearches"
    private let sessionKey = "tuji.cache.sessionId"
    private let maxRecent = 10

    private init() {
        let d = UserDefaults.standard
        favoriteIds = Set((d.array(forKey: favsKey) as? [String]) ?? [])
        let legacyEnglish = Set((d.array(forKey: learnedKey) as? [String]) ?? [])
        let english = Set((d.array(forKey: learnedEnKey) as? [String]) ?? [])
            .union(legacyEnglish)
        let japanese = Set((d.array(forKey: learnedJaKey) as? [String]) ?? [])
        learnedByLanguage = ["en": english, "ja": japanese]
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

    var learnedIds: Set<String> {
        self.learnedByLanguage[self.currentTargetLanguage] ?? []
    }

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
        var current = self.learnedIds
        guard !current.contains(id) else { return }
        current.insert(id)
        self.learnedByLanguage[self.currentTargetLanguage] = current
        persistLearned()
    }

    /// Drops the locally-cached learned set. Called after the server wipes
    /// learning progress (DELETE /api/users/progress) so completion % /
    /// category breakdown reset immediately and the next sign-in sync
    /// doesn't re-upload the cleared ids (sync is union-only). Favorites
    /// and settings are intentionally left untouched.
    func clearLearned() {
        guard self.learnedByLanguage.values.contains(where: { !$0.isEmpty }) else { return }
        self.learnedByLanguage = ["en": [], "ja": []]
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
        var current = self.learnedIds
        current.formUnion(learned)
        self.learnedByLanguage[self.currentTargetLanguage] = current
        persistFavorites()
        persistLearned()
    }

    /// Snapshot uploaded to POST /api/users/sync at sign-in time.
    var syncSnapshot: SyncPayload {
        SyncPayload(
            favorites: Array(favoriteIds).sorted(),
            learned: Array(self.learnedIds).sorted(),
            learningDirection: SettingsStore.shared.current.learningDirection
        )
    }

    // MARK: - Private

    private func persistFavorites() {
        UserDefaults.standard.set(Array(favoriteIds), forKey: favsKey)
    }

    private func persistLearned() {
        UserDefaults.standard.set(
            Array(self.learnedByLanguage["en"] ?? []),
            forKey: self.learnedEnKey
        )
        UserDefaults.standard.set(
            Array(self.learnedByLanguage["ja"] ?? []),
            forKey: self.learnedJaKey
        )
        UserDefaults.standard.removeObject(forKey: self.learnedKey)
    }

    private var currentTargetLanguage: String {
        SettingsStore.shared.current.learningDirection.targetLanguage
    }
}

struct SyncPayload: Codable {
    let favorites: [String]
    let learned: [String]
    let learningDirection: LearningDirection
}
