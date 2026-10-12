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
        AssistantIntent.parse(text, categories: AssistantFixture.categories)
    }

    @Test
    func blankInputHasNoIntent() {
        #expect(self.parse("") == nil)
        #expect(self.parse("  \n ") == nil)
    }

    @Test(arguments: ["有哪些分類", "分类", "categories", "カテゴリを見せて", "主題"])
    func asksForTheCategoryList(_ text: String) {
        #expect(self.parse(text) == .categories)
    }

    @Test(arguments: ["廚房", "kitchen", "Kitchen", "廚房分類", "show me the kitchen category"])
    func namesOneCategory(_ text: String) {
        #expect(self.parse(text) == .category(id: "kitchen"))
    }

    /// 「廚房用具」 is a thing to look up, not the 廚房 category — a category
    /// name only wins on its own, or when the text also says 分類.
    @Test
    func aCategoryNameInsideALongerWordIsALookup() {
        #expect(self.parse("廚房用具") == .lookup(query: "廚房用具"))
    }

    @Test(arguments: ["我的收藏", "favorites", "saved", "お気に入り"])
    func asksForFavoritesOverview(_ text: String) {
        #expect(self.parse(text) == .favorites)
    }

    @Test(arguments: ["書籤", "我的书签", "bookmarks", "ブックマーク"])
    func asksForBookmarks(_ text: String) {
        #expect(self.parse(text) == .bookmarks)
    }

    @Test(arguments: ["物見收藏", "物见", "saved sightings"])
    func asksForSavedCards(_ text: String) {
        #expect(self.parse(text) == .savedCards)
    }

    /// 「收藏的合集」 contains 「收藏」 too — the narrower word has to win.
    @Test(arguments: ["收藏的合集", "saved collections", "コレクション"])
    func asksForSavedCollections(_ text: String) {
        #expect(self.parse(text) == .savedCollections)
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
    private let catalog = AssistantCatalog()
    private let bookmarks = AssistantBookmarks()
    private let shelf = AssistantShelf()
    private let language = FakeLanguageContext(learningDirection: .zhJa)

    private func responder(signedIn: Bool = true) -> LocalAssistantResponder {
        LocalAssistantResponder(
            dictionary: self.dictionary,
            catalog: self.catalog,
            bookmarks: self.bookmarks,
            collections: self.shelf,
            language: self.language,
            isSignedIn: { signedIn }
        )
    }

    private func manyWords(_ count: Int, category: String = "kitchen") -> [CardWord] {
        (0..<count).map { AssistantFixture.word("w\($0)", word: "pan\($0)", category: category) }
    }

    @Test
    func greetingOffersTheThreeThingsItCanDo() {
        let reply = self.responder().greeting()
        #expect(reply.outcome == .greeting)
        #expect(reply.suggestions == [.categories, .favorites, .lookupPrompt])
    }

    /// `custom` and `community` are rows in the categories table, but they are
    /// sources, and a theme with no words behind it is not worth offering.
    @Test
    func listsTheThemesThatHaveWords() async {
        self.catalog.categories = AssistantFixture.categories + [
            AssistantFixture.category("custom", name: "Custom", nameZh: "自製圖鑑"),
            AssistantFixture.category("community", name: "Sightings", nameZh: "物見"),
            AssistantFixture.category("empty", name: "Empty", nameZh: "空的")
        ]
        self.dictionary.words = [
            AssistantFixture.word("pan", category: "kitchen"),
            AssistantFixture.word("shirt", category: "clothing"),
            AssistantFixture.word("atlas:mine", category: "custom"),
            AssistantFixture.word("saved:theirs", category: "community")
        ]
        let reply = await self.responder().reply(to: .categories)
        #expect(reply.outcome == .categories)
        #expect(reply.attachment == .categories(AssistantFixture.categories))
    }

    @Test
    func aCatalogueThatHasNotArrivedIsNotAnEmptyList() async {
        self.catalog.categories = []
        let reply = await self.responder().reply(to: .categories)
        #expect(reply.outcome == .categoriesUnavailable)
        #expect(reply.attachment == nil)
    }

    @Test
    func aCategoryShowsAFewCardsAndPointsAtTheRest() async {
        self.dictionary.words = self.manyWords(8) + [AssistantFixture.word("shirt", category: "clothing")]
        let reply = await self.responder().reply(to: .category(id: "kitchen"))
        #expect(reply.outcome == .category)
        guard case let .words(shown, total, more) = reply.attachment else {
            Issue.record("expected a words attachment")
            return
        }
        #expect(shown.count == LocalAssistantResponder.previewLimit)
        #expect(total == 8)
        #expect(more == .categoryDetail(id: "kitchen"))
        #expect(shown.allSatisfy { $0.category == "kitchen" })
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
    func bookmarksAreTheDictionaryWordsTheCacheHolds() async {
        self.dictionary.words = [AssistantFixture.word("a"), AssistantFixture.word("b"), AssistantFixture.word("c")]
        // `gone` is bookmarked but not in the current direction's dictionary.
        self.bookmarks.favoriteIds = ["a", "c", "gone"]
        let reply = await self.responder().reply(to: .bookmarks)
        #expect(reply.outcome == .bookmarks)
        #expect(reply.attachment == .words(
            [AssistantFixture.word("a"), AssistantFixture.word("c")],
            total: 2,
            more: nil
        ))
    }

    @Test
    func savedCardsAreTheSavedNamespaceOnly() async {
        self.dictionary.words = [
            AssistantFixture.word("plain"),
            AssistantFixture.word("atlas:mine"),
            AssistantFixture.word("saved:theirs")
        ]
        let reply = await self.responder().reply(to: .savedCards)
        #expect(reply.outcome == .savedCards)
        #expect(reply.attachment == .words([AssistantFixture.word("saved:theirs")], total: 1, more: nil))
    }

    @Test
    func nothingKeptYetIsItsOwnAnswer() async {
        let responder = self.responder()
        #expect(await responder.reply(to: .bookmarks).outcome == .nothingKept)
        #expect(await responder.reply(to: .savedCards).outcome == .nothingKept)
        #expect(await responder.reply(to: .savedCollections).outcome == .nothingKept)
    }

    /// The overview is answered from the device alone — it must not wait on the
    /// one read that needs the network.
    @Test
    func theFavoritesOverviewDoesNotTouchTheNetwork() async {
        let reply = await self.responder().reply(to: .favorites)
        #expect(reply.outcome == .favorites)
        #expect(reply.suggestions == [.bookmarks, .savedCards, .savedCollections])
        #expect(self.shelf.requestedLanguages.isEmpty)
    }

    @Test
    func savedCollectionsAreReadForTheLanguageBeingLearned() async {
        self.shelf.result = .success([AssistantFixture.collection("one"), AssistantFixture.collection("two")])
        let reply = await self.responder().reply(to: .savedCollections)
        #expect(reply.outcome == .collections)
        #expect(reply.attachment == .collections([
            AssistantFixture.collection("one"),
            AssistantFixture.collection("two")
        ]))
        #expect(self.shelf.requestedLanguages == [.ja])
    }

    @Test
    func aSignedOutUserIsToldWhyRatherThanShownAFailure() async {
        let reply = await self.responder(signedIn: false).reply(to: .savedCollections)
        #expect(reply.outcome == .collectionsNeedSignIn)
        #expect(self.shelf.requestedLanguages.isEmpty)
    }

    @Test
    func anUnreachableShelfIsAReplyNotAnError() async {
        self.shelf.result = .failure(ShelfUnreachable())
        let reply = await self.responder().reply(to: .savedCollections)
        #expect(reply.outcome == .collectionsUnreachable)
        #expect(reply.attachment == nil)
        // What still works offline.
        #expect(reply.suggestions == [.bookmarks, .savedCards])
    }

    @Test
    func blankTextHasNoReply() async {
        #expect(await self.responder().reply(toText: "   ") == nil)
    }

    /// 「保存」 asks for the favourites and is also a word a learner may be
    /// looking up. The command wins; the word stays one tap away.
    @Test
    func aCommandWordThatIsAlsoAnEntryOffersTheLookup() async {
        self.dictionary.words = [AssistantFixture.word("hozon", word: "保存")]
        let reply = await self.responder().reply(toText: "保存")
        #expect(reply?.outcome == .favorites)
        #expect(reply?.suggestions.first == .lookup(query: "保存"))
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

@MainActor
struct AssistantChatModelTests {
    private let dictionary = AssistantDictionary([AssistantFixture.word("cat")])
    private let shelf = AssistantShelf()

    private func model() -> AssistantChatModel {
        AssistantChatModel(responder: LocalAssistantResponder(
            dictionary: self.dictionary,
            catalog: AssistantCatalog(),
            bookmarks: AssistantBookmarks(),
            collections: self.shelf,
            language: FakeLanguageContext(),
            isSignedIn: { true }
        ))
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
        #expect(model.suggestions == [.categories, .favorites, .lookupPrompt])
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
        model.choose(.categories)
        await model.settle()
        #expect(self.outcomes(model) == [.greeting, nil, .categories])
    }

    @Test
    func chipsFollowTheLatestReply() async {
        let model = self.model()
        model.choose(.favorites)
        await model.settle()
        #expect(model.suggestions == [.bookmarks, .savedCards, .savedCollections])

        model.choose(.categories)
        await model.settle()
        #expect(model.suggestions.isEmpty)
    }

    /// 收藏的合集 is the one slow answer. A question asked while it is still
    /// out must get the only reply — not its own answer first and the stale
    /// one underneath it.
    @Test
    func aSlowAnswerIsDroppedOnceAnotherQuestionIsAsked() async {
        self.shelf.holds = true
        self.shelf.result = .success([AssistantFixture.collection("one")])
        let model = self.model()

        model.choose(.savedCollections)
        while self.shelf.gate == nil {
            await Task.yield()
        }
        model.send("cat")
        self.shelf.holds = false
        self.shelf.release()
        await model.settle()
        // Let the overtaken task run to its guard.
        for _ in 0..<10 {
            await Task.yield()
        }

        #expect(self.outcomes(model) == [.greeting, nil, nil, .words])
        #expect(!model.replying)
    }
}
