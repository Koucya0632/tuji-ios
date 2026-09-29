// 詞條延伸內容, fetched per word and kept for the session.
//
// The answer depends on the word, the interface language, the learning
// direction and the account's tier, so all four are in the cache key — buying
// a membership shows the unlocked text on the next open without a relaunch.
//
// Under membership policy v1 it never asks: `MemberAccess` says the feature is
// hidden, so v1 costs no request at all.

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

    private var cache: [String: WordInsights?] = [:]

    private let repository: WordInsightsRepository
    private let language: LanguageContext
    private let access: any MemberAccessReading

    init(
        repository: WordInsightsRepository = LiveWordInsightsRepository.shared,
        language: LanguageContext = SettingsStore.shared,
        access: any MemberAccessReading = LiveMemberAccess()
    ) {
        self.repository = repository
        self.language = language
        self.access = access
    }

    func key(for wordId: String) -> String {
        "\(self.language.learningDirection.rawValue)|\(self.language.uiLang)|\(self.access.tier.rawValue)|\(wordId)"
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
        guard Self.isEligible(wordId), self.access.level(.wordInsights) != .hidden else { return }
        let key = self.key(for: wordId)
        guard self.cache[key] == nil else { return }
        do {
            let response = try await self.repository.insights(wordId: wordId)
            self.cache[key] = .some(response.insights)
        } catch {
            // A failed read shows nothing and is asked again next time.
        }
    }

    /// The account changed: its tier, and so every cached answer, may differ.
    func reset() {
        self.cache = [:]
    }
}
