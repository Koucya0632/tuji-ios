// 詞條延伸內容, fetched per word and kept for the session.
//
// The answer depends on the word, the interface language, the learning
// direction and the account's tier, so all four are in the cache key — buying
// a membership shows the unlocked text on the next open without a relaunch.
//
// Under membership policy v1 the server says `available: false`; the store
// remembers that and stops asking, so v1 costs one request per session, not
// one per word opened.

import Foundation
import Observation

@MainActor
protocol WordInsightsRepository {
    func insights(wordId: String) async throws -> WordInsightsResponse
}

@MainActor
struct LiveWordInsightsRepository: WordInsightsRepository {
    static let shared = LiveWordInsightsRepository()

    private let api: APIClient
    private let settings: LanguageContext

    init(api: APIClient = .shared, settings: LanguageContext = SettingsStore.shared) {
        self.api = api
        self.settings = settings
    }

    func insights(wordId: String) async throws -> WordInsightsResponse {
        try await self.api.get(.wordInsights(
            id: wordId,
            lang: self.settings.uiLang,
            learning: self.settings.learningDirection.rawValue
        ))
    }
}

@MainActor
@Observable
final class WordInsightsStore {
    static let shared = WordInsightsStore()

    /// nil until the server has answered once.
    private(set) var available: Bool?
    private var cache: [String: WordInsights?] = [:]

    private let repository: WordInsightsRepository
    private let language: LanguageContext
    private let tier: () -> MembershipTier

    init(
        repository: WordInsightsRepository = LiveWordInsightsRepository.shared,
        language: LanguageContext = SettingsStore.shared,
        tier: @escaping () -> MembershipTier = { LiveEffectiveEntitlement.shared.tier }
    ) {
        self.repository = repository
        self.language = language
        self.tier = tier
    }

    func key(for wordId: String) -> String {
        "\(self.language.learningDirection.rawValue)|\(self.language.uiLang)|\(self.tier().rawValue)|\(wordId)"
    }

    /// The cached answer, if this word has been asked about under the current key.
    func cached(for wordId: String) -> WordInsights?? {
        self.cache[self.key(for: wordId)]
    }

    /// Official words only; 自製 and 物見 ids have no insights.
    static func isEligible(_ wordId: String) -> Bool {
        wordId.atlasItemId == nil && wordId.savedCommunitySlug == nil
    }

    func load(_ wordId: String) async {
        guard Self.isEligible(wordId), self.available != false else { return }
        let key = self.key(for: wordId)
        guard self.cache[key] == nil else { return }
        do {
            let response = try await self.repository.insights(wordId: wordId)
            self.available = response.available
            self.cache[key] = .some(response.insights)
        } catch {
            // A failed read shows nothing and is asked again next time.
        }
    }

    /// The account changed: its tier, and so every cached answer, may differ.
    func reset() {
        self.available = nil
        self.cache = [:]
    }
}
