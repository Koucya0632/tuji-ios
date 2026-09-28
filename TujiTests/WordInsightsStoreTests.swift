// 詞條延伸內容 on the client: when the store asks, and what it keeps.

import Foundation
import Testing
@testable import Tuji

@MainActor
private final class FakeInsightsRepository: WordInsightsRepository {
    var response = WordInsightsResponse(available: true, insights: nil)
    var fail = false
    private(set) var calls: [String] = []

    func insights(wordId: String) async throws -> WordInsightsResponse {
        self.calls.append(wordId)
        if self.fail { throw APIError.server(status: 500, body: nil) }
        return self.response
    }
}

@MainActor
private final class FakeLanguage: LanguageContext {
    var uiLang = "zh-Hant"
    var learningDirection: LearningDirection = .zhEn
}

private let sample = WordInsights(
    confusables: [WordInsightConfusable(term: "tap", catalogId: nil, distinction: "英式英文常說 tap")],
    mistakes: [],
    usage: nil,
    lockedMistakesCount: 1,
    usageLocked: false
)

@MainActor
struct WordInsightsStoreTests {
    @Test
    func v1IsAskedOncePerSessionNotOncePerWord() async {
        let repo = FakeInsightsRepository()
        repo.response = WordInsightsResponse(available: false, insights: nil)
        let store = WordInsightsStore(repository: repo, language: FakeLanguage(), tier: { .free })
        await store.load("faucet")
        await store.load("sofa")
        await store.load("rug")
        #expect(repo.calls == ["faucet"])
        #expect(store.available == false)
    }

    @Test
    func aWordIsAskedOnceAndServedFromMemory() async {
        let repo = FakeInsightsRepository()
        repo.response = WordInsightsResponse(available: true, insights: sample)
        let store = WordInsightsStore(repository: repo, language: FakeLanguage(), tier: { .free })
        await store.load("faucet")
        await store.load("faucet")
        #expect(repo.calls.count == 1)
        #expect(store.cached(for: "faucet") == .some(sample))
    }

    @Test
    func becomingAMemberAsksAgain() async {
        let repo = FakeInsightsRepository()
        repo.response = WordInsightsResponse(available: true, insights: sample)
        var tier = MembershipTier.free
        let store = WordInsightsStore(repository: repo, language: FakeLanguage(), tier: { tier })
        await store.load("faucet")
        tier = .lifetime
        #expect(store.cached(for: "faucet") == nil)
        await store.load("faucet")
        #expect(repo.calls.count == 2)
    }

    @Test
    func aDirectionOrLanguageSwitchAsksAgain() async {
        let repo = FakeInsightsRepository()
        let language = FakeLanguage()
        let store = WordInsightsStore(repository: repo, language: language, tier: { .free })
        await store.load("faucet")
        language.learningDirection = .zhJa
        await store.load("faucet")
        language.uiLang = "en"
        await store.load("faucet")
        #expect(repo.calls.count == 3)
    }

    @Test
    func customAndSavedWordsAreNeverAsked() async {
        let repo = FakeInsightsRepository()
        let store = WordInsightsStore(repository: repo, language: FakeLanguage(), tier: { .free })
        await store.load("atlas:123e4567-e89b-12d3-a456-426614174000")
        await store.load("saved:some-slug")
        #expect(repo.calls.isEmpty)
    }

    @Test
    func aFailureIsNotRememberedAsNothing() async {
        let repo = FakeInsightsRepository()
        repo.fail = true
        let store = WordInsightsStore(repository: repo, language: FakeLanguage(), tier: { .free })
        await store.load("faucet")
        #expect(store.cached(for: "faucet") == nil)
        repo.fail = false
        repo.response = WordInsightsResponse(available: true, insights: sample)
        await store.load("faucet")
        #expect(store.cached(for: "faucet") == .some(sample))
    }

    @Test
    func signOutForgetsV1AndEveryAnswer() async {
        let repo = FakeInsightsRepository()
        repo.response = WordInsightsResponse(available: false, insights: nil)
        let store = WordInsightsStore(repository: repo, language: FakeLanguage(), tier: { .free })
        await store.load("faucet")
        store.reset()
        #expect(store.available == nil)
        await store.load("faucet")
        #expect(repo.calls.count == 2)
    }
}
