// 助手, tier one — the three things a test can reach without a screen: how free
// text is read, what the device-only responder answers, and what the
// conversation does with a reply.
//
// Every assertion is on a decision (`AssistantIntent`, `AssistantReply.Outcome`,
// the attachment), never on a sentence: CI reads English and a laptop reads
// 繁體中文.

import Foundation
import Testing
@testable import Tuji

// MARK: - 讀懂一句話

struct AssistantIntentTests {
    private func parse(_ text: String) -> AssistantIntent? {
        AssistantIntent.parse(text)
    }

    @Test
    func blankInputHasNoIntent() {
        #expect(self.parse("") == nil)
        #expect(self.parse("  \n ") == nil)
    }

    /// 分類 and 收藏 are no longer things the assistant answers — typed, they
    /// are words like any other.
    @Test(arguments: ["分類", "我的收藏", "bookmarks", "お気に入り"])
    func formerCommandWordsAreLookups(_ text: String) {
        #expect(self.parse(text) == .lookup(query: text.lowercased()))
    }

    @Test(arguments: [
        ("apple", "apple"),
        ("查 apple", "apple"),
        ("查詢蘋果", "蘋果"),
        ("look up Apple", "apple"),
        ("りんごとは", "りんご"),
        ("「蘋果」是什麼意思？", "蘋果")
    ])
    func everythingElseIsALookupWithTheCommandStripped(_ text: String, _ query: String) {
        #expect(self.parse(text) == .lookup(query: query))
    }

    @Test(arguments: ["查單字", "查", "search", "word"])
    func aLookupWithNoWordAsksForOne(_ text: String) {
        #expect(self.parse(text) == .lookupPrompt)
    }
}

// MARK: - 本機回答

@MainActor
struct LocalAssistantResponderTests {
    private let dictionary = AssistantDictionary()

    private func responder() -> LocalAssistantResponder {
        LocalAssistantResponder(dictionary: self.dictionary)
    }

    private func manyWords(_ count: Int, category: String = "kitchen") -> [CardWord] {
        (0..<count).map { AssistantFixture.word("w\($0)", word: "pan\($0)", category: category) }
    }

    @Test
    func greetingOffersALookup() {
        let reply = self.responder().greeting()
        #expect(reply.outcome == .greeting)
        #expect(reply.suggestions == [.lookupPrompt])
    }

    @Test
    func aLookupUsesTheSearchRankingAndLinksToTheFullResults() async {
        self.dictionary.words = [
            AssistantFixture.word("contains", word: "wildcat"),
            AssistantFixture.word("exact", word: "cat"),
            AssistantFixture.word("miss", word: "dog")
        ]
        let reply = await self.responder().reply(to: .lookup(query: "cat"))
        #expect(reply.outcome == .words)
        guard case let .words(shown, total, more) = reply.attachment else {
            Issue.record("expected a words attachment")
            return
        }
        #expect(shown.map(\.id) == ["exact", "contains"])
        #expect(total == 2)
        // Everything fits in the preview, so there is no "rest" to point at.
        #expect(more == nil)
    }

    @Test
    func aLongLookupPointsAtSearch() async {
        self.dictionary.words = self.manyWords(9)
        let reply = await self.responder().reply(to: .lookup(query: "pan"))
        guard case let .words(shown, total, more) = reply.attachment else {
            Issue.record("expected a words attachment")
            return
        }
        #expect(shown.count == LocalAssistantResponder.previewLimit)
        #expect(total == 9)
        #expect(more == .search(query: "pan"))
    }

    @Test
    func aLookupThatFindsNothingSaysSoAndOffersAWayOn() async {
        let reply = await self.responder().reply(to: .lookup(query: "zzz"))
        #expect(reply.outcome == .noMatch)
        #expect(reply.attachment == nil)
        #expect(!reply.suggestions.isEmpty)
    }

    @Test
    func blankTextHasNoReply() async {
        #expect(await self.responder().reply(toText: "   ") == nil)
    }

    @Test
    func aPlainLookupDoesNotOfferItselfAgain() async {
        self.dictionary.words = [AssistantFixture.word("cat")]
        let reply = await self.responder().reply(toText: "cat")
        #expect(reply?.outcome == .words)
        #expect(reply?.suggestions.isEmpty == true)
    }
}

// MARK: - 對話

/// Answers like the device responder, except that the one question named
/// `slow` waits at a gate — the stand-in for a model call still out.
@MainActor
private final class GatedResponder: AssistantResponding {
    private let inner: LocalAssistantResponder
    var gate: CheckedContinuation<Void, Never>?

    init(dictionary: AssistantDictionary) {
        self.inner = LocalAssistantResponder(dictionary: dictionary)
    }

    func greeting() -> AssistantReply {
        self.inner.greeting()
    }

    func reply(toText text: String) async -> AssistantReply? {
        await self.inner.reply(toText: text)
    }

    func reply(to intent: AssistantIntent) async -> AssistantReply {
        if intent == .lookup(query: "slow") {
            await withCheckedContinuation { self.gate = $0 }
        }
        return await self.inner.reply(to: intent)
    }

    func release() {
        self.gate?.resume()
        self.gate = nil
    }
}

@MainActor
struct AssistantChatModelTests {
    private let dictionary = AssistantDictionary([AssistantFixture.word("cat")])

    private func model() -> AssistantChatModel {
        AssistantChatModel(responder: LocalAssistantResponder(dictionary: self.dictionary))
    }

    private func outcomes(_ model: AssistantChatModel) -> [AssistantReply.Outcome?] {
        model.messages.map { message in
            if case let .mascot(reply) = message.body { reply.outcome } else { nil }
        }
    }

    @Test
    func opensWithTheGreetingAndItsChips() {
        let model = self.model()
        #expect(self.outcomes(model) == [.greeting])
        #expect(model.suggestions == [.lookupPrompt])
    }

    @Test
    func aQuestionAddsWhatWasSaidAndThenTheAnswer() async {
        let model = self.model()
        model.send("  cat ")
        #expect(model.messages.last?.body == .user("cat"))
        #expect(model.replying)

        await model.settle()
        #expect(self.outcomes(model) == [.greeting, nil, .words])
        #expect(!model.replying)
    }

    @Test
    func blankInputIsNotAMessage() async {
        let model = self.model()
        model.send("   ")
        await model.settle()
        #expect(model.messages.count == 1)
        #expect(!model.replying)
    }

    /// A chip is its intent — it does not go back through the keyword rules,
    /// which would read 「查單字」's label differently in each language.
    @Test
    func aChipIsAnsweredAsItsIntent() async {
        let model = self.model()
        model.choose(.lookupPrompt)
        await model.settle()
        #expect(self.outcomes(model) == [.greeting, nil, .lookupPrompt])
    }

    @Test
    func chipsFollowTheLatestReply() async {
        let model = self.model()
        model.choose(.lookup(query: "zzz"))
        await model.settle()
        #expect(model.suggestions == [.lookupPrompt])

        model.choose(.lookup(query: "cat"))
        await model.settle()
        #expect(model.suggestions.isEmpty)
    }

    /// A question asked while an earlier answer is still out must get the only
    /// reply — not its own answer first and the stale one underneath it.
    @Test
    func aSlowAnswerIsDroppedOnceAnotherQuestionIsAsked() async {
        let responder = GatedResponder(dictionary: self.dictionary)
        let model = AssistantChatModel(responder: responder)

        model.choose(.lookup(query: "slow"))
        while responder.gate == nil {
            await Task.yield()
        }
        model.send("cat")
        responder.release()
        await model.settle()
        // Let the overtaken task run to its guard.
        for _ in 0..<10 {
            await Task.yield()
        }

        #expect(self.outcomes(model) == [.greeting, nil, nil, .words])
        #expect(!model.replying)
    }
}
