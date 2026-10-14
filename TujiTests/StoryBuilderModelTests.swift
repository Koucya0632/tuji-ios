// 情境故事 — the choices, and the one paid step at the end.
//
// Assertions are on decisions (what is picked, the payload, the failure case),
// never on a sentence: CI reads English and a laptop reads 繁體中文.

import Foundation
import Testing
@testable import Tuji

@MainActor
private final class StoryWriterFake: AssistantStoryWriting {
    var offer: Result<StoryOffer, Error> = .success(StoryWriterFake.offer())
    var result: Result<StoryResult, Error> = .success(StoryWriterFake.result())
    private(set) var offerLanguages: [String] = []
    private(set) var written: [StoryPayload] = []

    static func offer(available: Int = 100) -> StoryOffer {
        StoryOffer(
            minPoints: 3,
            maxPoints: 10,
            available: available,
            scenes: [
                .init(id: "supermarket", label: "超市", situations: [
                    .init(id: "shopping", label: "買東西"), .init(id: "chat", label: "閒聊")
                ]),
                .init(id: "office", label: "辦公室", situations: [.init(id: "work", label: "工作溝通")])
            ],
            levels: [.init(id: "starter", label: "入門", hint: "短句")]
        )
    }

    static func result(available: Int = 96) -> StoryResult {
        StoryResult(
            story: Story(
                title: "t",
                intro: "i",
                segments: [.init(
                    speaker: .cat, text: "りんごがあります。", furigana: nil, reading: nil,
                    translation: "有蘋果。", wordIds: ["apple"]
                )],
                wordNotes: nil
            ),
            charged: 4,
            available: available,
            minPoints: 3,
            maxPoints: 10
        )
    }

    func storyOffer(uiLanguage: String) async throws -> StoryOffer {
        self.offerLanguages.append(uiLanguage)
        return try self.offer.get()
    }

    func writeStory(_ payload: StoryPayload) async throws -> StoryResult {
        self.written.append(payload)
        return try self.result.get()
    }
}

@MainActor
private final class StoryRequestIds {
    private var issued = 0
    func next() -> String {
        self.issued += 1
        return "request-\(self.issued)"
    }
}

@MainActor
struct StoryBuilderModelTests {
    private let writer = StoryWriterFake()
    private let ids = StoryRequestIds()
    private let dictionary = AssistantDictionary([
        AssistantFixture.word("apple", word: "りんご", chinese: "蘋果"),
        AssistantFixture.word("banana"),
        AssistantFixture.word("pen"),
        AssistantFixture.word("cup"),
        AssistantFixture.word("atlas:7c0d5a3e-0000-4000-8000-000000000001", word: "招き猫"),
        AssistantFixture.word("saved:taken-in-card", category: "community", authorHandle: "TJ00000001"),
        AssistantFixture.word("saved:blocked-authors-card", category: "community", authorHandle: "TJ00000002")
    ])

    private func makeModel() -> StoryBuilderModel {
        StoryBuilderModel(
            repository: self.writer,
            dictionary: self.dictionary,
            language: FakeLanguageContext(uiLang: "zh-Hant", learningDirection: .zhJa),
            makeRequestId: self.ids.next,
            isBlocked: { $0 == "TJ00000002" }
        )
    }

    /// Everything picked: apple, 超市, 買東西, 入門.
    private func readyModel() async -> StoryBuilderModel {
        let model = self.makeModel()
        await model.loadOffer()
        model.toggle(self.dictionary.words[0])
        model.chooseScene("supermarket")
        model.chooseSituation("shopping")
        model.chooseLevel("starter")
        return model
    }

    @Test
    func offerIsReadInTheInterfaceLanguage() async {
        let model = self.makeModel()
        await model.loadOffer()
        #expect(self.writer.offerLanguages == ["zh-Hant"])
        #expect(model.offerPhase == .loaded)
        #expect(model.offer?.scenes.count == 2)
    }

    @Test
    func aFailedOfferReadIsAFailureNotAnEmptyList() async {
        self.writer.offer = .failure(APIError.transport(URLError(.notConnectedToInternet)))
        let model = self.makeModel()
        await model.loadOffer()
        #expect(model.offerPhase == .failed)
    }

    @Test
    func candidatesAreOfficialOwnAndTakenInCardsButNotABlockedAuthors() {
        let ids = self.makeModel().candidates.map(\.id)
        #expect(ids.contains("apple"))
        #expect(ids.contains("atlas:7c0d5a3e-0000-4000-8000-000000000001"))
        #expect(ids.contains("saved:taken-in-card"))
        #expect(!ids.contains("saved:blocked-authors-card"))
    }

    @Test
    func atMostThreeItemsAndTappingAgainRemovesOne() {
        let model = self.makeModel()
        for word in self.dictionary.words.prefix(4) {
            model.toggle(word)
        }
        #expect(model.picked.map(\.id) == ["apple", "banana", "pen"])
        #expect(!model.canPickMore)
        model.toggle(self.dictionary.words[1])
        #expect(model.picked.map(\.id) == ["apple", "pen"])
    }

    @Test
    func changingThePlaceClearsTheSituation() async {
        let model = await self.readyModel()
        model.chooseScene("office")
        #expect(model.situationId == nil)
        #expect(!model.isComplete)
    }

    @Test
    func aSituationFromAnotherPlaceIsNotAccepted() async {
        let model = self.makeModel()
        await model.loadOffer()
        model.chooseScene("office")
        model.chooseSituation("shopping")
        #expect(model.situationId == nil)
    }

    @Test
    func nothingIsWrittenUntilEveryChoiceIsMade() async {
        let model = self.makeModel()
        await model.loadOffer()
        model.toggle(self.dictionary.words[0])
        model.chooseScene("supermarket")
        await model.write()
        #expect(self.writer.written.isEmpty)
    }

    @Test
    func aBalanceUnderTheCeilingCannotWrite() async {
        self.writer.offer = .success(StoryWriterFake.offer(available: 9))
        let model = await self.readyModel()
        #expect(model.isComplete)
        #expect(!model.canAfford)
        await model.write()
        #expect(self.writer.written.isEmpty)
    }

    @Test
    func aStoryIsWrittenFromTheChoicesAndTheBalanceFollowsIt() async {
        let model = await self.readyModel()
        await model.write()
        #expect(self.writer.written == [StoryPayload(
            requestId: "request-1", uiLanguage: "zh-Hant", learningDirection: "zh-ja",
            wordIds: ["apple"], sceneId: "supermarket", situationId: "shopping", levelId: "starter"
        )])
        #expect(model.story?.segments.count == 1)
        #expect(model.offer?.available == 96)
        #expect(model.writing == .idle)
    }

    @Test
    func aRetryOfTheSameChoicesIsTheSameRequest() async {
        self.writer.result = .failure(APIError.transport(URLError(.timedOut)))
        let model = await self.readyModel()
        await model.write()
        #expect(model.writing == .failed(.offline))
        self.writer.result = .success(StoryWriterFake.result())
        await model.write()
        #expect(self.writer.written.map(\.requestId) == ["request-1", "request-1"])
    }

    @Test
    func newChoicesAreANewRequest() async {
        self.writer.result = .failure(APIError.server(status: 503, body: nil))
        let model = await self.readyModel()
        await model.write()
        model.chooseSituation("chat")
        #expect(model.writing == .idle)
        await model.write()
        #expect(self.writer.written.map(\.requestId) == ["request-1", "request-2"])
    }

    @Test
    func afterAStoryTheSameChoicesWriteANewOne() async {
        let model = await self.readyModel()
        await model.write()
        model.closeStory()
        #expect(model.story == nil)
        #expect(model.isComplete)
        await model.write()
        #expect(self.writer.written.map(\.requestId) == ["request-1", "request-2"])
    }

    @Test(arguments: [
        (APIError.conflict(reason: "insufficient_credits", message: nil), StoryBuilderModel.Failure.insufficientPoints),
        (APIError.rateLimited(message: nil), .busy),
        (APIError.transport(URLError(.notConnectedToInternet)), .offline),
        (APIError.forbidden, .unavailable),
        (APIError.notFound, .unavailable),
        (APIError.server(status: 400, body: nil), .itemsChanged),
        (APIError.server(status: 503, body: nil), .failed)
    ] as [(APIError, StoryBuilderModel.Failure)])
    func everyFailureSaysWhatHappened(error: APIError, expected: StoryBuilderModel.Failure) async {
        self.writer.result = .failure(error)
        let model = await self.readyModel()
        await model.write()
        #expect(model.writing == .failed(expected))
        #expect(model.story == nil)
    }
}
