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
private final class FakeAccess: MemberAccessReading {
    var policy: MemberPolicy = .v2
    var tier: MembershipTier = .free

    func level(_ feature: MemberFeature, hasOwnData: Bool) -> MemberAccessLevel {
        MemberAccess.level(feature, policy: self.policy, tier: self.tier, hasOwnData: hasOwnData)
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
    func v1NeverAsks() async {
        let repo = FakeInsightsRepository()
        let access = FakeAccess()
        access.policy = .v1
        let store = WordInsightsStore(repository: repo, language: FakeLanguage(), access: access)
        await store.load("faucet")
        await store.load("sofa")
        #expect(repo.calls.isEmpty)
    }

    @Test
    func aWordIsAskedOnceAndServedFromMemory() async {
        let repo = FakeInsightsRepository()
        repo.response = WordInsightsResponse(available: true, insights: sample)
        let store = WordInsightsStore(repository: repo, language: FakeLanguage(), access: FakeAccess())
        await store.load("faucet")
        await store.load("faucet")
        #expect(repo.calls.count == 1)
        #expect(store.cached(for: "faucet") == .some(sample))
    }

    @Test
    func becomingAMemberAsksAgain() async {
        let repo = FakeInsightsRepository()
        repo.response = WordInsightsResponse(available: true, insights: sample)
        let access = FakeAccess()
        let store = WordInsightsStore(repository: repo, language: FakeLanguage(), access: access)
        await store.load("faucet")
        access.tier = .lifetime
        #expect(store.cached(for: "faucet") == nil)
        await store.load("faucet")
        #expect(repo.calls.count == 2)
    }

    @Test
    func aDirectionOrLanguageSwitchAsksAgain() async {
        let repo = FakeInsightsRepository()
        let language = FakeLanguage()
        let store = WordInsightsStore(repository: repo, language: language, access: FakeAccess())
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
        let store = WordInsightsStore(repository: repo, language: FakeLanguage(), access: FakeAccess())
        await store.load("atlas:123e4567-e89b-12d3-a456-426614174000")
        await store.load("saved:some-slug")
        #expect(repo.calls.isEmpty)
    }

    @Test
    func aFailureIsNotRememberedAsNothing() async {
        let repo = FakeInsightsRepository()
        repo.fail = true
        let store = WordInsightsStore(repository: repo, language: FakeLanguage(), access: FakeAccess())
        await store.load("faucet")
        #expect(store.cached(for: "faucet") == nil)
        repo.fail = false
        repo.response = WordInsightsResponse(available: true, insights: sample)
        await store.load("faucet")
        #expect(store.cached(for: "faucet") == .some(sample))
    }

    @Test
    func signOutForgetsEveryAnswer() async {
        let repo = FakeInsightsRepository()
        repo.response = WordInsightsResponse(available: true, insights: sample)
        let store = WordInsightsStore(repository: repo, language: FakeLanguage(), access: FakeAccess())
        await store.load("faucet")
        store.reset()
        #expect(store.cached(for: "faucet") == nil)
        await store.load("faucet")
        #expect(repo.calls.count == 2)
    }
}
