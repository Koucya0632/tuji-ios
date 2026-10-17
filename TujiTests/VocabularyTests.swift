import Foundation
import Testing
@testable import Tuji

@MainActor
final class VocabularyTestViewer: ViewerIdentity {
    var uid: String? = "TJvocabulary"
    var authorRef: AtlasAuthorRef? {
        nil
    }

    func owns(handle: String) -> Bool {
        self.uid == handle
    }

    func displayName(fallback: String) -> String {
        fallback
    }
}

@MainActor
final class VocabularyTestJournal: VocabularyJournaling {
    var entries: [String: [VocabularyInput]] = [:]
    func pending(owner: String) -> [VocabularyInput] {
        self.entries[owner] ?? []
    }

    func save(_ input: VocabularyInput, owner: String) {
        self.remove(id: input.requestId, owner: owner)
        self.entries[owner, default: []].append(input)
    }

    func remove(id: String, owner: String) {
        self.entries[owner]?.removeAll { $0.requestId == id }
    }
}

enum VocabularyFixtures {
    /// Exported by the backend's typed fixtures. Decoding this catches wire-shape drift.
    static func records() throws -> [VocabularyRecord] {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("Fixtures/vocabulary-contracts.json")
        return try JSONDecoder().decode([VocabularyRecord].self, from: Data(contentsOf: url))
    }
}

@MainActor
final class VocabularyTestAPI: VocabularyStudying {
    var calls: [VocabularyInput] = []
    var offers = 0
    var available = 100
    var enabled = true
    var reason: VocabularyOffer.Reason?
    var loseResponse = false
    var fail = false
    var hold = false
    var reject: APIError?
    var continuation: CheckedContinuation<Void, Never>?
    var saved: [String: VocabularyRecord] = [:]
    var fixtures: [VocabularyRecord]

    init() throws {
        self.fixtures = try VocabularyFixtures.records()
    }

    func offer() async throws -> VocabularyOffer {
        self.offers += 1
        return VocabularyOffer(
            enabled: self.enabled && self.reason == nil,
            reason: self.reason,
            available: self.available,
            pricingVersion: "vocabulary-2026-10-v1",
            modes: VocabularyMode.allCases.map { .init(mode: $0, minPoints: 1, maxPoints: $0 == .analysis ? 10 : 5) }
        )
    }

    func generate(_ input: VocabularyInput) async throws -> VocabularyRecord {
        self.calls.append(input)
        if let reject { throw reject }
        if self.hold { await withCheckedContinuation { self.continuation = $0 } }
        let fixture = self.fixtures.first { $0.input?.mode == input.mode }
        let record = VocabularyRecord(
            id: input.requestId,
            status: self.fail ? .failed : .completed,
            input: input,
            result: self.fail ? nil : fixture?.result,
            charged: self.fail ? 0 : 3,
            favorite: false,
            createdAt: "2026-10-17T10:00:00.000Z",
            templateVersion: "vocabulary-2026-10-v1",
            error: self.fail ? "generation_failed" : nil
        )
        self.saved[record.id] = record
        if self.loseResponse { throw APIError.transport(URLError(.timedOut)) }
        return record
    }

    func record(id: String) async throws -> VocabularyRecord {
        guard let value = self.saved[id] else { throw APIError.notFound }
        return value
    }

    func records(learning: String, favorite: Bool, cursor: String?) async throws -> VocabularyRecords {
        VocabularyRecords(records: self.saved.values.filter {
            $0.input?.learningDirection == learning && (!favorite || $0.favorite)
        }, nextCursor: nil)
    }

    func favorite(id: String, value: Bool) async throws -> VocabularyRecord {
        let r = try await self.record(id: id)
        let updated = VocabularyRecord(
            id: r.id,
            status: r.status,
            input: r.input,
            result: r.result,
            charged: r.charged,
            favorite: value,
            createdAt: r.createdAt,
            templateVersion: r.templateVersion,
            error: r.error
        )
        self.saved[id] = updated
        return updated
    }

    func delete(id: String) async throws {
        self.saved[id] = nil
    }
}

@MainActor
struct VocabularyTests {
    /// One per test: Swift Testing makes a new instance for each.
    private let offerCache = Self.offerCache()

    private func model(
        _ api: VocabularyStudying,
        journal: VocabularyJournaling = VocabularyTestJournal(),
        viewer: VocabularyTestViewer = VocabularyTestViewer(),
        language: FakeLanguageContext = FakeLanguageContext(learningDirection: .zhEn),
        dictionary: FakeDictionary = FakeDictionary(words: []),
        offerCache: AssistantOfferCache<VocabularyOffer>? = nil
    )
        -> VocabularyModel
    {
        VocabularyModel(
            query: "borrow",
            repository: api,
            offerCache: offerCache ?? self.offerCache,
            language: language,
            identity: viewer,
            journal: journal,
            dictionary: dictionary,
            pollInterval: .milliseconds(1)
        )
    }

    @Test
    func threeBackendContractsDecodeDistinctly() throws {
        let records = try VocabularyFixtures.records()
        #expect(records.count == 3)
        if case .lookup = records[0].result?.content {} else { Issue.record("Expected lookup") }
        if case .analysis = records[1].result?.content {} else { Issue.record("Expected analysis") }
        if case .mnemonic = records[2].result?.content {} else { Issue.record("Expected mnemonic") }
    }

    /// Its own defaults, so no test reads an offer another one kept.
    private static func offerCache(_ defaults: UserDefaults? = nil) -> AssistantOfferCache<VocabularyOffer> {
        AssistantOfferCache(
            defaultsKey: "offer",
            defaults: defaults ?? UserDefaults(suiteName: "vocabulary-offer-\(UUID().uuidString)") ?? .standard
        )
    }

    @Test
    func aReturnVisitDoesNotReadTheBalanceAgain() async throws {
        let api = try VocabularyTestAPI()
        await self.model(api).load()
        api.available = 7
        let again = self.model(api)
        await again.load()
        #expect(api.offers == 1)
        #expect(again.offer?.available == 100)
        #expect(again.offerCurrent)
        #expect(again.canGenerate)
    }

    @Test
    func aDeliveredPurchaseMakesTheOpenPageReadTheBalanceAgain() async throws {
        let api = try VocabularyTestAPI(), model = self.model(api)
        await model.load()
        let revision = model.offerRevision
        api.available = 300
        self.offerCache.balanceChanged()
        #expect(model.offerRevision != revision)
        await model.load()
        #expect(api.offers == 2)
        #expect(model.offer?.available == 300)
        #expect(model.offerCurrent)
    }

    @Test
    func spendingReadsTheBalanceAgain() async throws {
        let api = try VocabularyTestAPI(), model = self.model(api)
        await model.load()
        api.available = 97
        await self.send(model)
        #expect(api.offers == 2)
        #expect(model.offer?.available == 97)
    }

    @Test
    func anOfferFromAnEarlierLaunchIsShownButCannotSpend() async throws {
        let api = try VocabularyTestAPI()
        let defaults = UserDefaults(suiteName: "vocabulary-offer-\(UUID().uuidString)") ?? .standard
        await self.model(api, offerCache: Self.offerCache(defaults)).load()
        // A relaunch: the memory is gone, the disk is not, and the server is out of reach.
        let failing = OfferControlAPI(api)
        failing.failOffer = true
        let relaunched = VocabularyModel(
            query: "borrow",
            repository: failing,
            offerCache: Self.offerCache(defaults),
            language: FakeLanguageContext(learningDirection: .zhEn),
            identity: VocabularyTestViewer(),
            journal: VocabularyTestJournal(),
            dictionary: FakeDictionary(words: []),
            pollInterval: .milliseconds(1)
        )
        await relaunched.load()
        #expect(relaunched.offer?.available == 100)
        #expect(!relaunched.offerCurrent)
        #expect(!relaunched.canGenerate)
        #expect(relaunched.message != nil)
    }

    @Test
    func theCacheJoinsAnAskOnItsWayAndKeepsAccountsApart() async throws {
        let api = try VocabularyTestAPI(), cache = Self.offerCache()
        async let first = cache.load(owner: "TJa") { try await api.offer() }
        async let second = cache.load(owner: "TJa") { try await api.offer() }
        _ = try await (first, second)
        #expect(api.offers == 1)
        #expect(cache.entry(owner: "TJa")?.current == true)
        #expect(cache.entry(owner: "TJb") == nil)
        cache.reset()
        #expect(cache.entry(owner: "TJa") == nil)
    }

    /// Types a word into the composer and sends it, as one tap on 送出 would.
    private func send(_ model: VocabularyModel, _ word: String = "borrow", mode: VocabularyMode? = nil) async {
        model.query = word
        if let mode { model.mode = mode }
        await model.generate()
    }

    @Test
    func entryTypingSwitchingAndChoosingNeverGenerate() async throws {
        let api = try VocabularyTestAPI(), model = self.model(api)
        await model.load()
        for mode in VocabularyMode.allCases {
            model.mode = mode
        }
        model.query = "bank"
        model.context = "the river bank"
        model.choose(VocabularyCandidate(term: "bank", meaning: "河岸"), mode: .analysis)
        #expect(api.calls.isEmpty)
        #expect(model.turns.isEmpty)
        #expect(model.canGenerate)
        #expect(model.context == "the river bank")
        #expect(model.mode == .analysis)
        #expect(model.selectedSense == "河岸")
    }

    @Test(arguments: VocabularyMode.allCases)
    func sendingClearsTheDraftAndTheCardArrivesAsATurn(_ mode: VocabularyMode) async throws {
        let api = try VocabularyTestAPI(), model = self.model(api)
        await model.load()
        model.mode = mode
        model.context = "I borrow books"
        await model.generate()
        #expect(api.calls.count == 1)
        #expect(api.calls[0].mode == mode)
        #expect(api.calls[0].query == "borrow")
        #expect(api.calls[0].context == "I borrow books")
        #expect(api.calls[0].maxPoints == (mode == .analysis ? 10 : 5))
        #expect(model.query.isEmpty)
        #expect(model.context.isEmpty)
        #expect(model.mode == mode)
        #expect(model.turns.map(\.id) == [api.calls[0].requestId])
        #expect(model.turns.last?.record?.status == .completed)
        #expect(model.spotlight?.id == api.calls[0].requestId)
        // An empty draft cannot be sent again by accident.
        await model.generate()
        #expect(api.calls.count == 1)
    }

    @Test
    func turnsStayInTheOrderTheyWereAsked() async throws {
        let api = try VocabularyTestAPI(), model = self.model(api)
        await model.load()
        await self.send(model, "borrow")
        await self.send(model, "lend", mode: .mnemonic)
        #expect(model.turns.map(\.input.query) == ["borrow", "lend"])
        #expect(model.turns.map(\.input.mode) == [.lookup, .mnemonic])
        #expect(model.turns.allSatisfy { $0.record?.status == .completed })
    }

    @Test
    func doubleTapCannotCreateASecondPaidRequest() async throws {
        let api = try VocabularyTestAPI(), model = self.model(api)
        await model.load()
        api.hold = true
        let task = Task { await model.generate() }
        while api.continuation == nil {
            await Task.yield()
        }
        // The pending turn is already on screen, without a card yet.
        #expect(model.turns.count == 1)
        #expect(model.turns[0].record == nil)
        model.query = "borrow"
        await model.generate()
        #expect(api.calls.count == 1)
        api.continuation?.resume()
        await task.value
        #expect(model.turns.count == 1)
        #expect(model.turns[0].record?.status == .completed)
    }

    @Test
    func lostResponseSurvivesRelaunchAndRetrievesOriginalResult() async throws {
        let api = try VocabularyTestAPI(), journal = VocabularyTestJournal()
        let model = self.model(api, journal: journal)
        await model.load()
        api.loseResponse = true
        await model.generate()
        #expect(model.pending != nil)
        #expect(model.turns.first?.record == nil)
        model.query = "borrow"
        #expect(!model.canGenerate)
        let relaunched = self.model(api, journal: journal)
        relaunched.query = ""
        await relaunched.load()
        #expect(relaunched.pending == nil)
        #expect(relaunched.turns.map(\.id) == model.turns.map(\.id))
        #expect(relaunched.turns.first?.record?.charged == 3)
        // The relaunched screen does not put the old question back into the draft.
        #expect(relaunched.query.isEmpty)
        #expect(api.calls.count == 1)
        #expect(journal.pending(owner: "TJvocabulary").isEmpty)
    }

    @Test
    func unseenRequestResendsTheSameAuthorizedIdentity() async throws {
        let api = try VocabularyTestAPI(), journal = VocabularyTestJournal()
        let input = try #require(VocabularyFixtures.records()[0].input)
        journal.save(input, owner: "TJvocabulary")
        let model = self.model(api, journal: journal)
        await model.load()
        #expect(api.calls.map(\.requestId) == [input.requestId])
        #expect(model.pending == nil)
        #expect(model.turns.map(\.id) == [input.requestId])
        #expect(model.turns.first?.record != nil)
    }

    @Test
    func terminalFailureCanOnlyGenerateAgainOnAnotherExplicitTap() async throws {
        let api = try VocabularyTestAPI(), model = self.model(api)
        await model.load()
        api.fail = true
        await model.generate()
        #expect(model.turns.last?.record?.status == .failed)
        #expect(model.turns.last?.failureNote != nil)
        #expect(model.pending == nil)
        await model.load()
        #expect(api.calls.count == 1)
        api.fail = false
        let failed = try #require(model.turns.last)
        model.edit(failed)
        #expect(model.query == "borrow")
        #expect(api.calls.count == 1)
        await model.generate()
        #expect(api.calls.count == 2)
        #expect(api.calls[0].requestId != api.calls[1].requestId)
        #expect(model.turns.count == 2)
    }

    @Test
    func rejectedRequestSaysWhyOnItsTurnAndEditRefillsTheDraft() async throws {
        let api = try VocabularyTestAPI(), journal = VocabularyTestJournal()
        let model = self.model(api, journal: journal)
        await model.load()
        api.reject = .conflict(reason: "price_changed", message: nil)
        model.mode = .analysis
        model.context = "I borrow books"
        await model.generate()
        let turn = try #require(model.turns.last)
        #expect(turn.rejection != nil)
        #expect(turn.record == nil)
        #expect(model.pending == nil)
        #expect(journal.pending(owner: "TJvocabulary").isEmpty)
        model.mode = .lookup
        model.edit(turn)
        #expect(model.query == "borrow")
        #expect(model.context == "I borrow books")
        #expect(model.mode == .analysis)
        #expect(api.calls.count == 1)
    }

    @Test
    func insufficientPointsInvalidInputAndDisabledFeatureCannotGenerate() async throws {
        let api = try VocabularyTestAPI(), model = self.model(api)
        api.available = 4
        await model.load()
        await model.generate()
        #expect(api.calls.isEmpty)
        api.available = 100
        self.offerCache.balanceChanged()
        await model.load()
        for query in [" ", "???", String(repeating: "a", count: 121)] {
            model.query = query
            await model.generate()
        }
        #expect(api.calls.isEmpty)
        model.query = "borrow"
        api.enabled = false
        self.offerCache.balanceChanged()
        await model.load()
        await model.generate()
        #expect(api.calls.isEmpty)
        #expect(model.turns.isEmpty)
    }

    @Test
    func languageOrAccountChangesClearTheConversation() async throws {
        let api = try VocabularyTestAPI(), viewer = VocabularyTestViewer(),
            language = FakeLanguageContext(learningDirection: .zhEn)
        let model = self.model(api, viewer: viewer, language: language)
        await model.load()
        await model.generate()
        #expect(model.turns.count == 1)
        language.learningDirection = .zhJa
        await model.load()
        #expect(model.turns.isEmpty)
        viewer.uid = "TJother"
        await model.load()
        #expect(model.turns.isEmpty)
        #expect(model.history.isEmpty)
    }

    @Test
    func favoritesHistoryAndDeletionNeverCallTheModel() async throws {
        let api = try VocabularyTestAPI(), model = self.model(api)
        await model.load()
        await model.generate()
        let record = try #require(model.turns.last?.record)
        await model.toggleFavorite(record)
        await model.loadHistory(favorite: true)
        #expect(model.history.count == 1)
        #expect(model.turns.last?.record?.favorite == true)
        // Reading 查詞紀錄 does not pour it into the conversation.
        #expect(model.turns.count == 1)
        api.enabled = false
        self.offerCache.balanceChanged()
        await model.load()
        await model.loadHistory(favorite: false)
        #expect(model.history.count == 1)
        await model.delete(record)
        #expect(model.history.isEmpty)
        #expect(model.turns.isEmpty)
        #expect(api.calls.count == 1)
    }

    @Test
    func endpointsCarryPrivateLanguageScopedContracts() {
        let list = Endpoint.vocabularyRecords(learning: "zh-ja", favorite: true, cursor: "id")
        let query = Dictionary(uniqueKeysWithValues: list.descriptor.queryItems.map { ($0.name, $0.value) })
        // 查詞紀錄 is scoped by learning direction alone.
        #expect(query["uiLanguage"] == nil)
        #expect(query["learningDirection"] == "zh-ja")
        for endpoint in [list, .vocabularyOffer, .vocabularyGenerate, .vocabularyRecord(id: "id")] {
            #expect(endpoint.descriptor.policy.access == .authenticated)
            #expect(endpoint.descriptor.policy.cachePolicy == .reloadIgnoringLocalCacheData)
        }
        #expect(Endpoint.vocabularyGenerate.descriptor.policy.timeout == 60)
    }

    @Test
    func changingInterfaceLanguageKeepsPaidCardsAndOpensThemFromHistory() async throws {
        let api = try VocabularyTestAPI(), language = FakeLanguageContext(learningDirection: .zhEn)
        let model = self.model(api, language: language)
        await model.load()
        await model.generate()
        let card = try #require(model.turns.last?.record)
        language.uiLang = "ja"
        await model.load()
        await model.loadHistory(favorite: false)
        #expect(model.history.map(\.id) == [card.id])
        // A card opened from 查詞紀錄 joins the conversation in the language it was made in, once.
        model.open(card)
        model.open(card)
        #expect(model.turns.map(\.id) == [card.id])
        #expect(model.turns.last?.input.uiLanguage == "zh-Hant")
        #expect(model.spotlight?.id == card.id)
        #expect(api.calls.count == 1)
    }

    @Test
    func blockersSayWhyGenerationIsClosed() async throws {
        let api = try VocabularyTestAPI(), model = self.model(api)
        await model.load()
        #expect(model.blocker == nil)
        api.reason = .membership
        self.offerCache.balanceChanged()
        await model.load()
        #expect(model.blocker == .membership)
        #expect(!model.canGenerate)
        api.reason = .disabled
        self.offerCache.balanceChanged()
        await model.load()
        #expect(model.blocker == .disabled)
        api.reason = nil
        api.available = 4
        self.offerCache.balanceChanged()
        await model.load()
        #expect(model.blocker == .insufficientPoints)
        await model.generate()
        #expect(api.calls.isEmpty)
    }

    @Test
    func catalogHintPointsOnlyAtOfficialWordsThatMatchExactly() throws {
        func word(_ id: String, _ text: String, _ chinese: String) -> CardWord {
            CardWord(
                id: id,
                word: text,
                chinese: chinese,
                imageUrl: "",
                category: "test",
                pronunciation: "",
                reading: nil
            )
        }
        let dictionary = FakeDictionary(words: [
            word("borrow", "borrow", "借入"),
            word("lend", "lend", "借出"),
            word("loan", "loan", "借出"),
            word("borrower", "borrower", "借款人"),
            word("atlas:1", "borrow", "借入"),
            word("saved:x", "borrow", "借入")
        ])
        let model = try self.model(VocabularyTestAPI(), dictionary: dictionary)
        #expect(model.catalogMatches.map(\.id) == ["borrow"])
        model.query = " 借入 "
        #expect(model.catalogMatches.map(\.id) == ["borrow"])
        model.query = "借出"
        #expect(model.catalogMatches.map(\.id) == ["lend", "loan"])
        model.query = "borro"
        #expect(model.catalogMatches.isEmpty)
    }

    @Test
    func onlyTheNewestCardOffersAnotherAndOnlyMnemonicAsTheMainAction() async throws {
        let api = try VocabularyTestAPI(), model = self.model(api)
        await model.load()
        await self.send(model, "borrow")
        let lookup = try #require(model.turns.last)
        #expect(model.regeneration(for: lookup) == .secondary(maxPoints: 5))
        await self.send(model, "borrow", mode: .mnemonic)
        let mnemonic = try #require(model.turns.last)
        #expect(model.regeneration(for: lookup) == nil)
        #expect(model.regeneration(for: mnemonic) == .main(maxPoints: 5))
        // Another card is a new paid request for the same question; both cards stay.
        await model.regenerate(mnemonic)
        #expect(api.calls.count == 3)
        #expect(api.calls[2].requestId != api.calls[1].requestId)
        #expect(api.calls[2].query == "borrow")
        #expect(api.calls[2].mode == .mnemonic)
        #expect(model.turns.count == 3)
        #expect(api.saved.count == 3)
        // An older card can no longer be regenerated.
        await model.regenerate(lookup)
        #expect(api.calls.count == 3)
        api.available = 4
        self.offerCache.balanceChanged()
        await model.load()
        #expect(try model.regeneration(for: #require(model.turns.last)) == nil)
    }
}

/// The test API, except that the offer cannot be read when `failOffer` is set.
@MainActor
final class OfferControlAPI: VocabularyStudying {
    let base: VocabularyTestAPI
    var failOffer = false
    init(_ base: VocabularyTestAPI) {
        self.base = base
    }

    func offer() async throws -> VocabularyOffer {
        if self.failOffer { throw APIError.transport(URLError(.notConnectedToInternet)) }
        return try await self.base.offer()
    }

    func generate(_ input: VocabularyInput) async throws -> VocabularyRecord {
        try await self.base.generate(input)
    }

    func record(id: String) async throws -> VocabularyRecord {
        try await self.base.record(id: id)
    }

    func records(learning: String, favorite: Bool, cursor: String?) async throws -> VocabularyRecords {
        try await self.base.records(learning: learning, favorite: favorite, cursor: cursor)
    }

    func favorite(id: String, value: Bool) async throws -> VocabularyRecord {
        try await self.base.favorite(id: id, value: value)
    }

    func delete(id: String) async throws {
        try await self.base.delete(id: id)
    }
}
