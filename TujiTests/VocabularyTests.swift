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
    var loseResponse = false
    var fail = false
    var hold = false
    var continuation: CheckedContinuation<Void, Never>?
    var saved: [String: VocabularyRecord] = [:]
    var fixtures: [VocabularyRecord]

    init() throws {
        self.fixtures = try VocabularyFixtures.records()
    }

    func offer() async throws -> VocabularyOffer {
        self.offers += 1
        return VocabularyOffer(
            enabled: self.enabled,
            available: self.available,
            pricingVersion: "vocabulary-2026-10-v1",
            modes: VocabularyMode.allCases.map { .init(mode: $0, minPoints: 1, maxPoints: $0 == .analysis ? 10 : 5) }
        )
    }

    func generate(_ input: VocabularyInput) async throws -> VocabularyRecord {
        self.calls.append(input)
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

    func records(
        uiLanguage: String,
        learning: String,
        favorite: Bool,
        cursor: String?
    ) async throws
        -> VocabularyRecords
    {
        VocabularyRecords(records: self.saved.values.filter {
            $0.input?.uiLanguage == uiLanguage && $0.input?.learningDirection == learning && (!favorite || $0.favorite)
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
    private func model(
        _ api: VocabularyTestAPI,
        journal: VocabularyJournaling = VocabularyTestJournal(),
        viewer: VocabularyTestViewer = VocabularyTestViewer(),
        language: FakeLanguageContext = FakeLanguageContext(learningDirection: .zhEn)
    )
        -> VocabularyModel
    {
        VocabularyModel(
            query: "borrow",
            repository: api,
            language: language,
            identity: viewer,
            journal: journal,
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
        #expect(model.canGenerate)
        #expect(model.context == "the river bank")
    }

    @Test(arguments: VocabularyMode.allCases)
    func anyModeCanGenerateDirectlyAndRevisitWithoutCharging(_ mode: VocabularyMode) async throws {
        let api = try VocabularyTestAPI(), model = self.model(api)
        await model.load()
        model.mode = mode
        await model.generate()
        #expect(api.calls.count == 1)
        #expect(api.calls[0].mode == mode)
        #expect(api.calls[0].maxPoints == (mode == .analysis ? 10 : 5))
        let saved = model.current
        model.mode = mode == .lookup ? .analysis : .lookup
        model.mode = mode
        #expect(model.current == saved)
        #expect(api.calls.count == 1)
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
        await model.generate()
        #expect(api.calls.count == 1)
        api.continuation?.resume()
        await task.value
        #expect(model.current?.status == .completed)
    }

    @Test
    func lostResponseSurvivesRelaunchAndRetrievesOriginalResult() async throws {
        let api = try VocabularyTestAPI(), journal = VocabularyTestJournal()
        let model = self.model(api, journal: journal)
        await model.load()
        api.loseResponse = true
        await model.generate()
        #expect(model.pending != nil)
        #expect(!model.canGenerate)
        let relaunched = self.model(api, journal: journal)
        await relaunched.load()
        #expect(relaunched.pending == nil)
        #expect(relaunched.current?.charged == 3)
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
    }

    @Test
    func terminalFailureCanOnlyGenerateAgainOnAnotherExplicitTap() async throws {
        let api = try VocabularyTestAPI(), model = self.model(api)
        await model.load()
        api.fail = true
        await model.generate()
        #expect(model.current?.status == .failed)
        #expect(model.pending == nil)
        await model.load()
        #expect(api.calls.count == 1)
        api.fail = false
        await model.generate()
        #expect(api.calls.count == 2)
        #expect(api.calls[0].requestId != api.calls[1].requestId)
    }

    @Test
    func insufficientPointsInvalidInputAndDisabledFeatureCannotGenerate() async throws {
        let api = try VocabularyTestAPI(), model = self.model(api)
        api.available = 4
        await model.load()
        await model.generate()
        #expect(api.calls.isEmpty)
        api.available = 100
        await model.load()
        for query in [" ", "???", String(repeating: "a", count: 121)] {
            model.query = query
            await model.generate()
        }
        #expect(api.calls.isEmpty)
        model.query = "borrow"
        api.enabled = false
        await model.load()
        await model.generate()
        #expect(api.calls.isEmpty)
    }

    @Test
    func editingDoesNotAttachOldResultsAndLanguageOrAccountChangesClearPrivateContent() async throws {
        let api = try VocabularyTestAPI(), viewer = VocabularyTestViewer(),
            language = FakeLanguageContext(learningDirection: .zhEn)
        let model = self.model(api, viewer: viewer, language: language)
        await model.load()
        await model.generate()
        #expect(model.current != nil)
        model.query = "lend"
        #expect(model.current == nil)
        model.query = "borrow"
        #expect(model.current != nil)
        language.learningDirection = .zhJa
        await model.load()
        #expect(model.results.isEmpty)
        viewer.uid = "TJother"
        await model.load()
        #expect(model.results.isEmpty)
        #expect(model.history.isEmpty)
    }

    @Test
    func favoritesHistoryAndDeletionNeverCallTheModel() async throws {
        let api = try VocabularyTestAPI(), model = self.model(api)
        await model.load()
        await model.generate()
        let record = try #require(model.current)
        await model.toggleFavorite(record)
        await model.loadHistory(favorite: true)
        #expect(model.history.count == 1)
        #expect(model.current?.favorite == true)
        api.enabled = false
        await model.load()
        await model.loadHistory(favorite: false)
        #expect(model.history.count == 1)
        await model.delete(record)
        #expect(model.history.isEmpty)
        #expect(model.current == nil)
        #expect(api.calls.count == 1)
    }

    @Test
    func endpointsCarryPrivateLanguageScopedContracts() {
        let list = Endpoint.vocabularyRecords(uiLanguage: "ja", learning: "zh-ja", favorite: true, cursor: "id")
        let query = Dictionary(uniqueKeysWithValues: list.descriptor.queryItems.map { ($0.name, $0.value) })
        #expect(query["uiLanguage"] == "ja")
        #expect(query["learningDirection"] == "zh-ja")
        for endpoint in [list, .vocabularyOffer, .vocabularyGenerate, .vocabularyRecord(id: "id")] {
            #expect(endpoint.descriptor.policy.access == .authenticated)
            #expect(endpoint.descriptor.policy.cachePolicy == .reloadIgnoringLocalCacheData)
        }
        #expect(Endpoint.vocabularyGenerate.descriptor.policy.timeout == 60)
    }
}
