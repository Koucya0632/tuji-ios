import Foundation
import Testing
@testable import Tuji

@MainActor
final class GrammarTestJournal: GrammarJournaling {
    var entries: [String: [GrammarInput]] = [:]
    func pending(owner: String) -> [GrammarInput] {
        self.entries[owner] ?? []
    }

    func save(_ input: GrammarInput, owner: String) {
        self.remove(id: input.requestId, owner: owner)
        self.entries[owner, default: []].append(input)
    }

    func remove(id: String, owner: String) {
        self.entries[owner]?.removeAll { $0.requestId == id }
    }
}

@MainActor
final class GrammarTestProgress: GrammarProgressStoring {
    var saved: [String: GrammarPracticeProgress] = [:]
    private func key(_ owner: String, _ learning: String, _ id: String) -> String {
        "\(owner)|\(learning)|\(id)"
    }

    func progress(owner: String, learning: String, setId: String) -> GrammarPracticeProgress {
        self.saved[self.key(owner, learning, setId)] ?? .init()
    }

    func save(_ progress: GrammarPracticeProgress, owner: String, learning: String, setId: String) {
        self.saved[self.key(owner, learning, setId)] = progress
    }

    func remove(owner: String, learning: String, setId: String) {
        self.saved[self.key(owner, learning, setId)] = nil
    }
}

enum GrammarFixtures {
    /// A byte-identical copy of tuji-web's tests/fixtures/grammar-contracts.json.
    static func records() throws -> [GrammarRecord] {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("Fixtures/grammar-contracts.json")
        return try JSONDecoder().decode([GrammarRecord].self, from: Data(contentsOf: url))
    }

    static func practice() throws -> GrammarPractice {
        guard case let .practice(value)? = try self.records()[2].result?.content else {
            throw CocoaError(.coderValueNotFound)
        }
        return value
    }
}

@MainActor
final class GrammarTestAPI: GrammarStudying {
    var calls: [GrammarInput] = []
    var available = 100
    var reason: GrammarOffer.Reason?
    var loseResponse = false
    var reject: APIError?
    var clarify = false
    var listed: [(favorite: Bool, mode: GrammarMode?)] = []
    var saved: [String: GrammarRecord] = [:]
    var fixtures: [GrammarRecord]

    init() throws {
        self.fixtures = try GrammarFixtures.records()
    }

    static let prices: [GrammarMode: Int] = [.explain: 8, .compare: 10, .practice: 20]

    func offer() async throws -> GrammarOffer {
        GrammarOffer(
            enabled: self.reason == nil,
            reason: self.reason,
            available: self.available,
            pricingVersion: "grammar-2026-10-v1",
            modes: GrammarMode.allCases.map { .init(mode: $0, minPoints: 1, maxPoints: Self.prices[$0]!) }
        )
    }

    func generate(_ input: GrammarInput) async throws -> GrammarRecord {
        self.calls.append(input)
        if let reject { throw reject }
        // As the server does: the balance is checked before anything is charged.
        if input.maxPoints > self.available { throw APIError.conflict(reason: "insufficient_credits", message: nil) }
        let fixture = self.fixtures.first { $0.input?.mode == input.mode }
        let result = self.clarify ? GrammarReply(
            outcome: "clarification",
            message: "這句有兩個語法，要看哪一個？",
            candidates: [
                GrammarCandidate(focus: "のに", description: "逆接"),
                GrammarCandidate(focus: "ずに", description: "不做就…")
            ],
            content: nil
        ) : fixture?.result
        let record = GrammarRecord(
            id: input.requestId,
            status: self.clarify ? .clarification : .completed,
            input: input,
            result: result,
            charged: self.clarify ? 0 : 4,
            favorite: false,
            createdAt: "2026-10-18T10:00:00.000Z",
            templateVersion: "grammar-2026-10-v1",
            error: nil
        )
        self.saved[record.id] = record
        if self.loseResponse { throw APIError.transport(URLError(.timedOut)) }
        return record
    }

    func record(id: String) async throws -> GrammarRecord {
        guard let value = self.saved[id] else { throw APIError.notFound }
        return value
    }

    func records(learning: String, favorite: Bool, mode: GrammarMode?, cursor: String?) async throws -> GrammarRecords {
        self.listed.append((favorite, mode))
        return GrammarRecords(records: self.saved.values.filter {
            $0.input?
                .learningDirection == learning && (!favorite || $0.favorite) && (mode == nil || $0.input?.mode == mode)
        }, nextCursor: nil)
    }

    func favorite(id: String, value: Bool) async throws -> GrammarRecord {
        let r = try await self.record(id: id)
        let updated = GrammarRecord(
            id: r.id, status: r.status, input: r.input, result: r.result, charged: r.charged,
            favorite: value, createdAt: r.createdAt, templateVersion: r.templateVersion, error: r.error
        )
        self.saved[id] = updated
        return updated
    }

    func delete(id: String) async throws {
        self.saved[id] = nil
    }
}

@MainActor
struct GrammarTests {
    /// One per test: Swift Testing makes a new instance for each.
    private let offerCache = AssistantOfferCache<GrammarOffer>(
        defaultsKey: "offer",
        defaults: UserDefaults(suiteName: "grammar-offer-\(UUID().uuidString)") ?? .standard
    )

    private func model(
        _ api: GrammarTestAPI,
        journal: GrammarJournaling = GrammarTestJournal(),
        progress: GrammarProgressStoring = GrammarTestProgress(),
        viewer: VocabularyTestViewer = VocabularyTestViewer(),
        language: FakeLanguageContext = FakeLanguageContext(learningDirection: .zhJa)
    )
        -> GrammarModel
    {
        GrammarModel(
            query: "〜たことがある",
            repository: api,
            offerCache: self.offerCache,
            historyCache: AssistantHistoryCache(),
            language: language,
            identity: viewer,
            journal: journal,
            progress: progress,
            pollInterval: .milliseconds(1)
        )
    }

    @Test
    func threeBackendContractsDecodeDistinctly() throws {
        let records = try GrammarFixtures.records()
        #expect(records.count == 3)
        if case .explain = records[0].result?.content {} else { Issue.record("Expected explain") }
        if case .compare = records[1].result?.content {} else { Issue.record("Expected compare") }
        if case let .practice(value) = records[2].result?.content {
            #expect(value.questions.count == 5)
            #expect(value.questions.allSatisfy { q in q.options.contains { $0.id == q.answer } })
        } else { Issue.record("Expected practice") }
    }

    @Test
    func theEntrySitsDirectlyUnderAIVocabulary() {
        #expect(Array(AssistantHomeFeature.allCases.prefix(2)) == [.lookup, .grammar])
        #expect(AssistantHomeFeature.grammar.route == .grammar)
        #expect(AssistantHomeFeature.grammar.symbol != AssistantHomeFeature.story.symbol)
    }

    @Test(arguments: GrammarMode.allCases)
    func sendingClearsTheDraftAndCarriesOnlyWhatTheModeReads(_ mode: GrammarMode) async throws {
        let api = try GrammarTestAPI(), model = self.model(api)
        await model.load()
        model.mode = mode
        model.compareWith = "〜ことがある"
        model.difficulty = .advanced
        model.practiceType = .context
        await model.generate()
        #expect(api.calls.count == 1)
        let sent = api.calls[0]
        #expect(sent.mode == mode)
        #expect(sent.maxPoints == GrammarTestAPI.prices[mode])
        #expect(sent.compareWith == (mode == .explain ? "" : "〜ことがある"))
        #expect(sent.difficulty == (mode == .practice ? .advanced : .basic))
        #expect(sent.practiceType == (mode == .practice ? .context : .mixed))
        #expect(model.query.isEmpty && model.compareWith.isEmpty)
        #expect(model.turns.last?.record?.status == .completed)
        await model.generate()
        #expect(api.calls.count == 1)
    }

    @Test
    func entrySwitchingNextStepsAndCandidatesNeverGenerate() async throws {
        let api = try GrammarTestAPI(), model = self.model(api)
        await model.load()
        for mode in GrammarMode.allCases {
            model.mode = mode
        }
        #expect(api.calls.isEmpty)
        let records = try GrammarFixtures.records()
        model.next(.practice, from: records[0])
        #expect(model.mode == .practice)
        #expect(model.query == "〜たことがある")
        model.follow(.explainB, from: records[1])
        #expect(model.mode == .explain)
        #expect(model.query == "〜ことがある")
        model.follow(.practice, from: records[1])
        #expect(model.mode == .practice)
        #expect(model.compareWith == "〜ことがある")
        #expect(api.calls.isEmpty)
        #expect(model.turns.isEmpty)
        // The drafted step records where it came from when it is finally sent.
        await model.generate()
        #expect(api.calls.first?.sourceRecordId == records[1].id)
    }

    @Test
    func typingOverADraftedStepMakesItANewQuestion() async throws {
        let api = try GrammarTestAPI(), model = self.model(api)
        await model.load()
        try model.next(.compare, from: GrammarFixtures.records()[0])
        model.query = "〜ばかり"
        model.editQuery()
        await model.generate()
        #expect(api.calls.first?.sourceRecordId == nil)
    }

    @Test
    func clarificationIsFreeAndItsChoiceOnlyFillsTheDraft() async throws {
        let api = try GrammarTestAPI(), model = self.model(api)
        await model.load()
        api.clarify = true
        model.query = "雨が降っているのに、傘を持たずに出かけた。"
        await model.generate()
        let turn = try #require(model.turns.last)
        #expect(turn.record?.status == .clarification)
        model.choose(GrammarCandidate(focus: "のに", description: "逆接"), for: turn)
        #expect(api.calls.count == 1)
        #expect(model.focus == "のに")
        #expect(model.query == "雨が降っているのに、傘を持たずに出かけた。")
        api.clarify = false
        await model.generate()
        #expect(api.calls.count == 2)
        #expect(api.calls[1].focus == "のに")
    }

    @Test
    func aLostResponseIsAskedAfterNotResentOrRecharged() async throws {
        let api = try GrammarTestAPI(), journal = GrammarTestJournal()
        let model = self.model(api, journal: journal)
        await model.load()
        api.loseResponse = true
        await model.generate()
        #expect(api.calls.count == 1)
        #expect(model.pending == nil)
        #expect(model.turns.first?.record?.status == .completed)
        let left = journal.entries.values.flatMap(\.self)
        #expect(left.isEmpty)
    }

    @Test
    func anUnansweredRequestSurvivesRelaunchAndIsRecoveredOnce() async throws {
        let api = try GrammarTestAPI(), journal = GrammarTestJournal()
        let first = self.model(api, journal: journal)
        await first.load()
        // The POST never got through.
        api.reject = nil
        let input = GrammarInput(
            requestId: UUID().uuidString.lowercased(), mode: .practice, query: "〜ために", context: "",
            compareWith: "〜ように", focus: "", difficulty: .basic, practiceType: .mixed, sourceRecordId: nil,
            uiLanguage: "zh-Hant", learningDirection: "zh-ja", pricingVersion: "grammar-2026-10-v1", maxPoints: 20
        )
        journal.save(input, owner: "TJvocabulary")
        let relaunched = self.model(api, journal: journal)
        relaunched.query = ""
        await relaunched.load()
        #expect(api.calls.map(\.requestId) == [input.requestId])
        #expect(relaunched.turns.first?.record?.status == .completed)
        #expect(relaunched.query.isEmpty)
    }

    @Test
    func pointsAndMembershipBlockSpendingButNotReading() async throws {
        let api = try GrammarTestAPI(), model = self.model(api)
        api.available = 9
        await model.load()
        model.mode = .compare
        // Not judged on the page: the server refuses it, and says why.
        #expect(model.blocker == nil)
        #expect(model.canGenerate)
        await model.generate()
        #expect(model.blocker == .insufficientPoints)
        #expect(api.saved.isEmpty)
        api.reason = .membership
        self.offerCache.balanceChanged()
        await model.load()
        #expect(model.blocker == .membership)
        api.saved["x"] = try GrammarFixtures.records()[0]
        await model.loadHistory(.init())
        #expect(model.history.count == 1)
    }

    @Test
    func oversizeInputIsBlockedBesideTheField() async throws {
        let api = try GrammarTestAPI(), model = self.model(api)
        await model.load()
        model.query = String(repeating: "あ", count: 801)
        #expect(model.tooLong && !model.canGenerate)
        model.query = "〜たことがある"
        model.mode = .compare
        model.compareWith = String(repeating: "あ", count: 121)
        #expect(model.tooLong && !model.canGenerate)
    }

    @Test
    func switchingAccountOrDirectionClearsTheConversationAndDraft() async throws {
        let api = try GrammarTestAPI(), language = FakeLanguageContext(learningDirection: .zhJa)
        let model = self.model(api, language: language)
        await model.load()
        await model.generate()
        model.query = "draft"
        model.compareWith = "b"
        language.learningDirection = .zhEn
        await model.load()
        #expect(model.turns.isEmpty)
        #expect(model.query.isEmpty && model.compareWith.isEmpty)
    }

    @Test
    func eachTemplateFilterKeepsItsOwnListAndDeletingDropsThem() async throws {
        let api = try GrammarTestAPI(), model = self.model(api)
        await model.load()
        model.mode = .practice
        await model.generate()
        model.query = "〜ばかり"
        model.mode = .explain
        await model.generate()
        await model.loadHistory(.init(favorite: false, mode: .practice))
        await model.loadHistory(.init(favorite: false, mode: .explain))
        await model.loadHistory(.init(favorite: false, mode: .practice))
        #expect(api.listed.count == 2)
        #expect(model.history.map(\.input?.mode) == [.practice])
        let set = try #require(model.history.first)
        await model.delete(set)
        await model.loadHistory(.init(favorite: false, mode: .explain))
        #expect(api.listed.count == 3)
    }

    @Test
    func historyFiltersByTemplateAndDeletingForgetsPracticeProgress() async throws {
        let api = try GrammarTestAPI(), progress = GrammarTestProgress(), model = self.model(api, progress: progress)
        await model.load()
        model.mode = .practice
        await model.generate()
        model.query = "〜ばかり"
        model.mode = .explain
        await model.generate()
        await model.loadHistory(.init(favorite: false, mode: .practice))
        #expect(model.history.map(\.input?.mode) == [.practice])
        #expect(api.listed.last?.mode == .practice)
        let set = try #require(model.history.first)
        progress.save(.init(attempts: [], revealed: true), owner: "TJvocabulary", learning: "zh-ja", setId: set.id)
        await model.delete(set)
        #expect(progress.saved.isEmpty)
        #expect(model.turns.count == 1)
    }

    @Test
    func onlyTheNewestPracticeSetOffersAnotherAsTheMainAction() async throws {
        let api = try GrammarTestAPI(), model = self.model(api)
        await model.load()
        model.mode = .practice
        await model.generate()
        let turn = try #require(model.turns.last)
        #expect(model.regeneration(for: turn) == .main(maxPoints: 20))
        await model.regenerate(turn)
        #expect(api.calls.count == 2)
        #expect(api.calls[1].requestId != api.calls[0].requestId)
        #expect(api.calls[1].query == api.calls[0].query)
        #expect(model.regeneration(for: turn) == nil)
    }
}

@MainActor
struct GrammarPracticeSessionTests {
    private func session(_ store: GrammarTestProgress = GrammarTestProgress()) throws -> GrammarPracticeSession {
        try GrammarPracticeSession(
            practice: GrammarFixtures.practice(),
            setId: "set",
            owner: "TJ",
            learning: "zh-ja",
            store: store
        )
    }

    private func answer(_ session: GrammarPracticeSession, rightly: (Int) -> Bool) {
        var index = 0
        while session.screen == .question, let question = session.question {
            let wrong = question.options.first { $0.id != question.answer }!.id
            session.select(rightly(index) ? question.answer : wrong)
            session.confirm()
            session.next()
            index += 1
        }
    }

    @Test
    func answersStayHiddenUntilConfirmedAndTheFirstChoiceIsFixed() throws {
        let session = try self.session()
        #expect(session.screen == .overview)
        session.start()
        #expect(session.screen == .question)
        #expect(session.position?.index == 1 && session.position?.total == 5)
        let question = try #require(session.question)
        session.select("a")
        #expect(session.confirmed == nil)
        // Moving on needs an answer first; nothing advances on its own.
        session.next()
        #expect(session.question?.id == question.id)
        session.confirm()
        #expect(session.confirmed == "a")
        session.select("b")
        session.confirm()
        #expect(session.confirmed == "a")
        session.next()
        #expect(session.position?.index == 2)
    }

    @Test
    func theFirstRunIsTheScoreAndRedoingNeverChangesIt() throws {
        let session = try self.session()
        session.start()
        self.answer(session) { $0 < 3 }
        #expect(session.screen == .summary)
        #expect(session.firstScore?.correct == 3)
        #expect(session.firstScore?.total == 5)
        let wrong = try session.wrong(in: #require(session.attempt))
        #expect(wrong.count == 2)
        session.redoWrong()
        #expect(session.position?.total == 2)
        self.answer(session) { _ in true }
        #expect(session.firstScore?.correct == 3)
        #expect(session.attempt?.isFirst == false)
        let redo = try #require(session.attempt)
        #expect(session.correct(in: redo) == 2)
        session.redoAll()
        #expect(session.position?.total == 5)
    }

    @Test
    func progressContinuesOnTheSameDeviceAndAnUnfinishedRunIsNotWrong() throws {
        let store = GrammarTestProgress()
        let first = try self.session(store)
        first.start()
        let question = try #require(first.question)
        first.select(question.answer)
        first.confirm()
        first.next()
        let reopened = try self.session(store)
        #expect(reopened.screen == .overview)
        #expect(reopened.unfinished?.answers.count == 1)
        #expect(reopened.firstScore?.answered == 1)
        reopened.start()
        #expect(reopened.position?.index == 2)
    }

    @Test
    func readingTheAnswersFirstMakesLaterAnsweringARedo() throws {
        let store = GrammarTestProgress()
        let session = try self.session(store)
        session.review()
        #expect(session.screen == .review)
        session.showOverview()
        session.start()
        #expect(session.attempt?.isFirst == false)
        self.answer(session) { _ in true }
        #expect(session.firstScore == nil)
        // Reading the answers after a finished first run leaves that score alone.
        let scored = try self.session(GrammarTestProgress())
        scored.start()
        self.answer(scored) { $0 == 0 }
        scored.review()
        #expect(scored.firstScore?.correct == 1)
    }
}
