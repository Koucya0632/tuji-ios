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
    private var learnedByLanguage: [TargetLanguage: Set<String>]
    private(set) var recentSearches: [String]
    let sessionId: String

    private let defaults: UserDefaults
    /// Read at call time: the cache outlives every direction switch.
    private let learningDirection: @MainActor () -> LearningDirection
    private let favsKey = "tuji.cache.favorites"
    private let legacyLearnedKey = "tuji.cache.learned"
    private let recentKey = "tuji.cache.recentSearches"
    private let sessionKey = "tuji.cache.sessionId"
    private let maxRecent = 10

    /// "tuji.cache.learned.en" / ".ja" — rawValue keeps the pre-enum keys.
    private static func learnedKey(for language: TargetLanguage) -> String {
        "tuji.cache.learned.\(language.rawValue)"
    }

    /// Internal so a test can stand one up over its own defaults — the account
    /// boundary below is the part worth asserting, and a `private init` over
    /// `.standard` made it unreachable.
    init(
        defaults: UserDefaults = .standard,
        learningDirection: @escaping @MainActor () -> LearningDirection = {
            SettingsStore.shared.current.learningDirection
        }
    ) {
        self.defaults = defaults
        self.learningDirection = learningDirection
        let d = defaults
        favoriteIds = Set((d.array(forKey: favsKey) as? [String]) ?? [])
        var learned: [TargetLanguage: Set<String>] = [:]
        for language in TargetLanguage.allCases {
            learned[language] = Set((d.array(forKey: Self.learnedKey(for: language)) as? [String]) ?? [])
        }
        // Pre-split installs stored a single (English) learned list.
        learned[.en, default: []]
            .formUnion(Set((d.array(forKey: legacyLearnedKey) as? [String]) ?? []))
        learnedByLanguage = learned
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
        self.learnedByLanguage = [:]
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
        self.defaults.set(recentSearches, forKey: recentKey)
    }

    func clearRecentSearches() {
        recentSearches = []
        self.defaults.set(recentSearches, forKey: recentKey)
    }

    // MARK: - Account boundary

    /// The account's server bookmarks, merged in after sign-in's upload. Union:
    /// a guest's bookmarks were uploaded a moment ago and are in `favorites`
    /// anyway, and nothing here may drop one the user can see.
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

    /// Sign-out. The bookmarks and learned ids here were this account's, and
    /// the next sign-in uploads whatever is here into *that* account — so
    /// keeping them handed one person's 書籤 to the next. Recent searches stay:
    /// they are this device's history, not an account's.
    func reset() {
        self.favoriteIds = []
        self.learnedByLanguage = [:]
        persistFavorites()
        persistLearned()
    }

    // MARK: - Sync

    /// Snapshot uploaded to POST /api/users/sync at sign-in time.
    var syncSnapshot: SyncPayload {
        SyncPayload(
            favorites: Array(favoriteIds).sorted(),
            learned: Array(self.learnedIds).sorted(),
            learningDirection: self.learningDirection()
        )
    }

    // MARK: - Private

    private func persistFavorites() {
        self.defaults.set(Array(favoriteIds), forKey: favsKey)
    }

    private func persistLearned() {
        for language in TargetLanguage.allCases {
            self.defaults.set(
                Array(self.learnedByLanguage[language] ?? []),
                forKey: Self.learnedKey(for: language)
            )
        }
        self.defaults.removeObject(forKey: self.legacyLearnedKey)
    }

    private var currentTargetLanguage: TargetLanguage {
        self.learningDirection().targetLanguage
    }
}

struct SyncPayload: Codable {
    let favorites: [String]
    let learned: [String]
    let learningDirection: LearningDirection
}
