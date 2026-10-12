// 助手, tier two — the device first, a model only for what the device cannot
// answer, and never without the person choosing to pay for it.
//
// Assertions are on decisions (`Outcome`, the payload), never on a
// sentence: CI reads English and a laptop reads 繁體中文.

import Foundation
import Testing
@testable import Tuji

private struct NotAllowed: Error {}

@MainActor
private final class AssistantModelFake: AssistantAsking {
    var offer: Result<AssistantOffer, Error> = .success(AssistantOffer(minPoints: 1, maxPoints: 5, available: 100))
    var answer: Result<AssistantAnswer, Error> = .success(AssistantModelFake.answer())
    private(set) var offersRead = 0
    private(set) var asked: [AssistantAskPayload] = []

    static func answer(
        _ text: String = "答案",
        inScope: Bool = true,
        wordIds: [String] = [],
        charged: Int = 2,
        available: Int = 98
    )
        -> AssistantAnswer
    {
        AssistantAnswer(
            answer: text,
            inScope: inScope,
            wordIds: wordIds,
            charged: charged,
            available: available,
            minPoints: 1,
            maxPoints: 5
        )
    }

    func assistantOffer() async throws -> AssistantOffer {
        self.offersRead += 1
        return try self.offer.get()
    }

    func askAssistant(_ payload: AssistantAskPayload) async throws -> AssistantAnswer {
        self.asked.append(payload)
        return try self.answer.get()
    }
}

@MainActor
private final class RequestIds {
    private var issued = 0
    func next() -> String {
        self.issued += 1
        return "request-\(self.issued)"
    }
}

@MainActor
struct TieredAssistantResponderTests {
    private let dictionary = AssistantDictionary([
        AssistantFixture.word("apple", word: "apple", chinese: "蘋果"),
        AssistantFixture.word("pear", word: "pear", chinese: "梨子")
    ])
    private let model = AssistantModelFake()
    private let language = FakeLanguageContext(uiLang: "ja", learningDirection: .zhEn)
    private let question = "apple 和 pear 差在哪"

    private func responder() -> TieredAssistantResponder {
        let ids = RequestIds()
        return TieredAssistantResponder(
            local: LocalAssistantResponder(
                dictionary: self.dictionary,
                catalog: AssistantCatalog(),
                bookmarks: AssistantBookmarks(),
                collections: AssistantShelf(),
                language: self.language,
                isSignedIn: { true }
            ),
            model: self.model,
            dictionary: self.dictionary,
            language: self.language,
            makeRequestId: { ids.next() }
        )
    }

    /// A free answer is not improved by a paid one: the model is not even
    /// priced while lookup is finding things.
    @Test
    func aLookupThatFindsSomethingNeverReachesTheModel() async {
        let reply = await self.responder().reply(toText: "apple")
        #expect(reply?.outcome == .words)
        #expect(self.model.offersRead == 0)
        #expect(self.model.asked.isEmpty)
    }

    @Test
    func anEmptyLookupOffersTheModelAndDoesNotAskIt() async {
        let reply = await self.responder().reply(toText: "  \(self.question) ")
        #expect(reply?.outcome == .modelOffer)
        #expect(reply?.suggestions.first == .askModel(question: self.question))
        // Typing never spends points. Only the chip does.
        #expect(self.model.asked.isEmpty)
    }

    @Test
    func anAccountThatCannotAskKeepsTheLookupAnswer() async {
        self.model.offer = .failure(APIError.forbidden)
        let reply = await self.responder().reply(toText: self.question)
        #expect(reply?.outcome == .noMatch)
        #expect(reply?.suggestions.contains(.askModel(question: self.question)) == false)
    }

    @Test
    func fewerPointsThanTheCeilingIsSaidInsteadOfOffered() async {
        self.model.offer = .success(AssistantOffer(minPoints: 1, maxPoints: 5, available: 4))
        let reply = await self.responder().reply(toText: self.question)
        #expect(reply?.outcome == .modelInsufficientPoints)
        #expect(reply?.suggestions.contains(.askModel(question: self.question)) == false)
    }

    @Test
    func thePriceIsReadOncePerConversation() async {
        let responder = self.responder()
        _ = await responder.reply(toText: self.question)
        _ = await responder.reply(toText: "zzz qqq")
        #expect(self.model.offersRead == 1)
    }

    @Test
    func askingSendsTheQuestionItsLanguagesAndTheWordsItMentions() async {
        self.model.answer = .success(AssistantModelFake.answer(wordIds: ["pear"]))
        let reply = await self.responder().reply(to: .askModel(question: self.question))

        let sent = self.model.asked.first
        #expect(sent?.question == self.question)
        #expect(sent?.uiLanguage == "ja")
        #expect(sent?.learningDirection == "zh-en")
        #expect(Set(sent?.wordIds ?? []) == ["apple", "pear"])
        #expect(sent?.history.isEmpty == true)

        #expect(reply.outcome == .modelAnswer)
        // The answer is the sentence. What it cost lives on 點數明細, and the
        // entries were grounding for the model, not a list to show again.
        #expect(reply.attachment == nil)
    }

    @Test
    func aFollowUpCarriesWhatTheModelSaid() async {
        let responder = self.responder()
        _ = await responder.reply(to: .askModel(question: "first"))
        _ = await responder.reply(to: .askModel(question: "second"))
        #expect(self.model.asked.last?.history == [
            AssistantTurn(role: .user, text: "first"),
            AssistantTurn(role: .assistant, text: "答案")
        ])
    }

    @Test
    func historyIsCappedAtTheServersLimit() async {
        let responder = self.responder()
        for index in 0..<6 {
            _ = await responder.reply(to: .askModel(question: "q\(index)"))
        }
        #expect(self.model.asked.last?.history.count == TieredAssistantResponder.historyLimit)
        #expect(self.model.asked.last?.history.last?.text == "答案")
    }

    @Test
    func aDeclinedQuestionCostsNothingAndIsNotCarriedForward() async {
        self.model.answer = .success(AssistantModelFake.answer("", inScope: false, charged: 0, available: 100))
        let responder = self.responder()
        let reply = await responder.reply(to: .askModel(question: "寫一段程式"))
        #expect(reply.outcome == .modelOutOfScope)
        // The server sent no sentence, so the app supplies one.
        #expect(!reply.text.isEmpty)

        self.model.answer = .success(AssistantModelFake.answer())
        _ = await responder.reply(to: .askModel(question: self.question))
        #expect(self.model.asked.last?.history.isEmpty == true)
    }

    /// The server charges a request id once. A resend after a lost response
    /// must be the same request, or a retry is a second charge.
    @Test
    func aRetryReusesTheRequestIdUntilItIsAnswered() async {
        let responder = self.responder()
        self.model.answer = .failure(APIError.transport(URLError(.timedOut)))
        let failed = await responder.reply(to: .askModel(question: self.question))
        #expect(failed.outcome == .modelOffline)
        #expect(failed.suggestions == [.askModel(question: self.question)])

        self.model.answer = .success(AssistantModelFake.answer())
        _ = await responder.reply(to: .askModel(question: self.question))
        _ = await responder.reply(to: .askModel(question: self.question))
        #expect(self.model.asked.map(\.requestId) == ["request-1", "request-1", "request-2"])
    }

    @Test
    func everyFailureIsAReply() async {
        let cases: [(Error, AssistantReply.Outcome)] = [
            (APIError.conflict(reason: "insufficient_credits", message: nil), .modelInsufficientPoints),
            (APIError.rateLimited(message: nil), .modelBusy),
            (APIError.transport(URLError(.notConnectedToInternet)), .modelOffline),
            (APIError.forbidden, .modelUnavailable),
            (APIError.notFound, .modelUnavailable),
            (APIError.server(status: 503, body: nil), .modelUnavailable),
            (NotAllowed(), .modelUnavailable)
        ]
        for (error, outcome) in cases {
            self.model.answer = .failure(error)
            let reply = await self.responder().reply(to: .askModel(question: self.question))
            #expect(reply.outcome == outcome)
        }
    }

    @Test
    func theBalanceAfterAnAnswerDecidesTheNextOffer() async {
        self.model.answer = .success(AssistantModelFake.answer(charged: 5, available: 3))
        let responder = self.responder()
        _ = await responder.reply(to: .askModel(question: self.question))
        let next = await responder.reply(toText: "zzz qqq")
        #expect(next?.outcome == .modelInsufficientPoints)
        // Known from the answer; not read again.
        #expect(self.model.offersRead == 0)
    }

    @Test
    func otherIntentsStayOnTheDevice() async {
        let reply = await self.responder().reply(to: .bookmarks)
        #expect(reply.outcome == .nothingKept)
        #expect(self.model.asked.isEmpty)
        #expect(self.model.offersRead == 0)
    }

    // MARK: 附帶的詞條

    @Test
    func aLatinWordMustBeAWholeWordToCount() {
        let words = [AssistantFixture.word("pan", word: "pan", chinese: "平底鍋")]
        #expect(TieredAssistantResponder.candidates(for: "Japan is far", in: words).isEmpty)
        #expect(TieredAssistantResponder.candidates(for: "what is a PAN?", in: words).map(\.id) == ["pan"])
    }

    @Test
    func aGlossOrACjkHeadwordCountsWhereverItAppears() {
        let words = [
            AssistantFixture.word("ringo", word: "りんご", chinese: "蘋果"),
            AssistantFixture.word("ki", word: "木", chinese: "樹")
        ]
        #expect(TieredAssistantResponder.candidates(for: "りんごの数え方は？", in: words).map(\.id) == ["ringo"])
        #expect(TieredAssistantResponder.candidates(for: "蘋果怎麼說", in: words).map(\.id) == ["ringo"])
        // One character is in half of everything.
        #expect(TieredAssistantResponder.candidates(for: "木曜日はいつ", in: words).isEmpty)
    }

    @Test
    func onlyCatalogueWordsAreSentLongestMentionFirstUpToTheLimit() {
        var words = (0..<12).map { AssistantFixture.word("w\($0)", word: "term\($0)", chinese: "") }
        words.append(AssistantFixture.word("atlas:mine", word: "mine", chinese: ""))
        words.append(AssistantFixture.word("saved:theirs", word: "theirs", chinese: ""))
        words.append(AssistantFixture.word("long", word: "longestterm", chinese: ""))
        let question = (0..<12).map { "term\($0)" }.joined(separator: " ") + " mine theirs longestterm"
        let picked = TieredAssistantResponder.candidates(for: question, in: words)
        #expect(picked.count == TieredAssistantResponder.wordLimit)
        #expect(picked.first?.id == "long")
        #expect(!picked.contains { $0.id.hasPrefix("atlas:") || $0.id.hasPrefix("saved:") })
    }
}
