// 個人詞表 on the client: which entry points show, how a refusal is presented,
// and what the store and the list screen do with the server's answers.
// Decisions only — copy is localized and not asserted here.

import Foundation
import Testing
@testable import Tuji

// MARK: - Fakes

@MainActor
private final class FakeWordListRepository: WordListRepository {
    var response = WordListsResponse(available: true, tier: "lifetime", canCreate: true, limits: nil, lists: [])
    var detailResponse: WordListDetailResponse?
    var failNext: Error?
    private(set) var listCalls = 0
    private(set) var reorders: [[String]] = []
    private(set) var queueCalls: [QueueCall] = []
    var queueResponse = StudyQueueResponse(queue: [], stats: nil)

    struct QueueCall {
        let listId: String
        let limit: Int
    }

    private func maybeFail() throws {
        if let error = self.failNext {
            self.failNext = nil
            throw error
        }
    }

    func lists(containing _: String?) async throws -> WordListsResponse {
        self.listCalls += 1
        try self.maybeFail()
        return self.response
    }

    func detail(id _: String) async throws -> WordListDetailResponse {
        try self.maybeFail()
        guard let detailResponse else { throw APIError.notFound }
        return detailResponse
    }

    func create(name: String) async throws -> WordList {
        try self.maybeFail()
        return list("new", name: name)
    }

    func rename(id _: String, name _: String) async throws {
        try self.maybeFail()
    }

    func delete(id _: String) async throws {
        try self.maybeFail()
    }

    func reorder(ids: [String]) async throws {
        try self.maybeFail()
        self.reorders.append(ids)
    }

    func setWord(_: String, inList _: String, present _: Bool) async throws {
        try self.maybeFail()
    }

    func queue(listId: String, mode _: StudyMode, limit: Int) async throws -> StudyQueueResponse {
        self.queueCalls.append(QueueCall(listId: listId, limit: limit))
        return self.queueResponse
    }
}

@MainActor
private final class FakeLanguage: LanguageContext {
    var uiLang = "zh-Hant"
    var learningDirection: LearningDirection = .zhEn
}

private func list(_ id: String, name: String = "L", count: Int = 0, locked: Bool = false) -> WordList {
    WordList(
        id: id,
        name: name,
        targetLanguage: "en",
        position: 0,
        wordCount: count,
        locked: locked,
        containsWord: nil
    )
}

private func detail(
    ids: [String] = ["a", "b"],
    stats: WordListStats = WordListStats(total: 2, seen: 1, due: 1),
    canEdit: Bool = true,
    canStudy: Bool = true
)
    -> WordListDetailResponse
{
    WordListDetailResponse(
        list: list("l1", count: ids.count),
        wordIds: ids,
        stats: stats,
        canEdit: canEdit,
        canStudy: canStudy,
        wordLimit: 500
    )
}

// MARK: - Rules

struct WordListRulesTests {
    @Test
    func unknownOrV1HidesEveryEntryPoint() {
        for available in [nil, false] as [Bool?] {
            #expect(WordListRules.browseEntry(available: available, tier: "pro", listCount: 3) == .hidden)
            #expect(WordListRules.addEntry(available: available, tier: "pro") == .hidden)
        }
    }

    @Test
    func aNonMemberMeetsALock() {
        #expect(WordListRules.browseEntry(available: true, tier: "free", listCount: 0) == .locked)
        #expect(WordListRules.addEntry(available: true, tier: "free") == .locked)
    }

    @Test
    func aRefundedNonMemberCanStillOpenTheirListsButNotAdd() {
        #expect(WordListRules.browseEntry(available: true, tier: "free", listCount: 2) == .open)
        #expect(WordListRules.addEntry(available: true, tier: "free") == .locked)
    }

    @Test
    func membersAreOpen() {
        for tier in ["lifetime", "pro"] {
            #expect(WordListRules.browseEntry(available: true, tier: tier, listCount: 0) == .open)
            #expect(WordListRules.addEntry(available: true, tier: tier) == .open)
        }
    }

    @Test
    func refusalsMapToWhatTheScreenDoes() {
        #expect(WordListWriteOutcome.from(APIError.paymentRequired(message: nil)) == .needsUpgrade)
        #expect(WordListWriteOutcome.from(APIError.rateLimited(message: nil)) == .atLimit)
        #expect(WordListWriteOutcome.from(APIError.notFound) == .missing)
        if case .failed = WordListWriteOutcome.from(APIError.server(status: 500, body: nil)) {} else {
            Issue.record("a 500 is a failure, not a paywall")
        }
    }
}

// MARK: - Store

@MainActor
struct WordListsStoreTests {
    @Test
    func loadsOncePerDirectionAndAgainAfterASwitch() async {
        let repo = FakeWordListRepository()
        let language = FakeLanguage()
        let store = WordListsStore(repository: repo, language: language)
        await store.loadIfNeeded()
        await store.loadIfNeeded()
        #expect(repo.listCalls == 1)
        language.learningDirection = .zhJa
        await store.loadIfNeeded()
        #expect(repo.listCalls == 2)
    }

    @Test
    func v1AnswerHidesTheFeature() async {
        let repo = FakeWordListRepository()
        repo.response = WordListsResponse(available: false, tier: nil, canCreate: nil, limits: nil, lists: [])
        let store = WordListsStore(repository: repo, language: FakeLanguage())
        await store.loadIfNeeded()
        #expect(store.browseEntry == .hidden)
        #expect(store.addEntry == .hidden)
    }

    @Test
    func aFailedDeletePutsTheListBack() async {
        let repo = FakeWordListRepository()
        repo.response = WordListsResponse(
            available: true, tier: "pro", canCreate: true, limits: nil, lists: [list("a"), list("b")]
        )
        let store = WordListsStore(repository: repo, language: FakeLanguage())
        await store.loadIfNeeded()
        repo.failNext = APIError.server(status: 500, body: nil)
        let outcome = await store.delete(list("a"))
        #expect(outcome != .done)
        #expect(store.lists.map(\.id) == ["a", "b"])
    }

    @Test
    func deletingAListAlreadyGoneCountsAsDone() async {
        let repo = FakeWordListRepository()
        repo.response = WordListsResponse(
            available: true,
            tier: "pro",
            canCreate: true,
            limits: nil,
            lists: [list("a")]
        )
        let store = WordListsStore(repository: repo, language: FakeLanguage())
        await store.loadIfNeeded()
        repo.failNext = APIError.notFound
        let outcome = await store.delete(list("a"))
        #expect(outcome == .done)
    }

    @Test
    func movingSendsTheWholeNewOrder() async {
        let repo = FakeWordListRepository()
        repo.response = WordListsResponse(
            available: true, tier: "pro", canCreate: true, limits: nil,
            lists: [list("a"), list("b"), list("c")]
        )
        let store = WordListsStore(repository: repo, language: FakeLanguage())
        await store.loadIfNeeded()
        _ = await store.move("c", by: -1)
        #expect(repo.reorders.last == ["a", "c", "b"])
        // Past either end is a no-op, not a request.
        _ = await store.move("a", by: -1)
        #expect(repo.reorders.count == 1)
    }

    @Test
    func addingAWordUpdatesTheRowItTouched() async {
        let repo = FakeWordListRepository()
        repo.response = WordListsResponse(
            available: true, tier: "pro", canCreate: true, limits: nil, lists: [list("a", count: 2)]
        )
        let store = WordListsStore(repository: repo, language: FakeLanguage())
        await store.loadIfNeeded()
        let outcome = await store.setWord("w", in: list("a", count: 2), present: true)
        #expect(outcome == .done)
        #expect(store.lists.first?.wordCount == 3)
        #expect(store.lists.first?.containsWord == true)
    }

    @Test
    func aNonMemberAddingIsSentToThePaywall() async {
        let repo = FakeWordListRepository()
        let store = WordListsStore(repository: repo, language: FakeLanguage())
        repo.failNext = APIError.paymentRequired(message: nil)
        let outcome = await store.setWord("w", in: list("a"), present: true)
        #expect(outcome == .needsUpgrade)
    }

    @Test
    func signOutForgetsEverything() async {
        let repo = FakeWordListRepository()
        repo.response = WordListsResponse(
            available: true,
            tier: "pro",
            canCreate: true,
            limits: nil,
            lists: [list("a")]
        )
        let store = WordListsStore(repository: repo, language: FakeLanguage())
        await store.loadIfNeeded()
        store.reset()
        #expect(store.available == nil)
        #expect(store.lists.isEmpty)
        #expect(store.browseEntry == .hidden)
        await store.loadIfNeeded()
        #expect(repo.listCalls == 2)
    }
}

// MARK: - One list

@MainActor
struct WordListDetailModelTests {
    @Test
    func offersOnlyTheModesWithSomethingInThem() async {
        let repo = FakeWordListRepository()
        let model = WordListDetailModel(listId: "l1", repository: repo)

        repo.detailResponse = detail(stats: WordListStats(total: 2, seen: 1, due: 1))
        await model.load()
        #expect(model.studyModes == [.new, .review])

        repo.detailResponse = detail(stats: WordListStats(total: 2, seen: 2, due: 0))
        await model.load()
        #expect(model.studyModes.isEmpty)

        repo.detailResponse = detail(stats: WordListStats(total: 2, seen: 0, due: 0))
        await model.load()
        #expect(model.studyModes == [.new])
    }

    @Test
    func aListThatCannotBeStudiedOffersNothingAndIsReadOnly() async {
        let repo = FakeWordListRepository()
        repo.detailResponse = detail(canEdit: false, canStudy: false)
        let model = WordListDetailModel(listId: "l1", repository: repo)
        await model.load()
        #expect(model.studyModes.isEmpty)
        #expect(model.isReadOnly)
    }

    @Test
    func aDeletedListIsReportedMissing() async {
        let repo = FakeWordListRepository()
        let model = WordListDetailModel(listId: "gone", repository: repo)
        await model.load()
        #expect(model.missing)
    }

    @Test
    func aRefusedRemovalPutsTheWordBack() async {
        let repo = FakeWordListRepository()
        repo.detailResponse = detail(ids: ["a", "b"])
        let model = WordListDetailModel(listId: "l1", repository: repo)
        await model.load()
        repo.failNext = APIError.server(status: 500, body: nil)
        _ = await model.remove("a")
        #expect(model.wordIds == ["a", "b"])
    }
}

// MARK: - Studying a list

@MainActor
struct WordListStudyQueueTests {
    @Test
    func neverServesAWarmQueue() {
        let queue = WordListStudyQueue(listId: "l1", repository: FakeWordListRepository())
        #expect(queue.take(mode: .new) == nil)
        #expect(queue.take(mode: .review) == nil)
    }

    @Test
    func newFollowsTheDailyGoalAndReviewIsCapped() async throws {
        let repo = FakeWordListRepository()
        let queue = WordListStudyQueue(listId: "l1", repository: repo, dailyGoal: { 15 })
        _ = try await queue.fetch(mode: .new)
        _ = try await queue.fetch(mode: .review)
        #expect(repo.queueCalls.map(\.listId) == ["l1", "l1"])
        #expect(repo.queueCalls.map(\.limit) == [15, 30])
    }

    @Test
    func theListQueueEndpointCarriesTheListNotTheThemes() {
        let d = Endpoint.studyWordListQueue(listId: "l1", mode: "new", limit: 10, lang: "zh-Hant", learning: "zh-en")
            .descriptor
        let names = Set(d.queryItems.map(\.name))
        #expect(d.path == "/api/study/queue")
        #expect(names.contains("list"))
        #expect(!names.contains("category"))
        #expect(d.queryItems.first { $0.name == "list" }?.value == "l1")
    }
}
