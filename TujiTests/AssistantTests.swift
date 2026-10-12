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

// MARK: - Fixtures

private enum Fixture {
    static func word(_ id: String, word: String? = nil, chinese: String = "", category: String = "kitchen")
        -> CardWord
    {
        CardWord(
            id: id,
            word: word ?? id,
            chinese: chinese,
            imageUrl: "",
            category: category,
            pronunciation: ""
        )
    }

    static func category(_ id: String, name: String, nameZh: String) -> TujiCategory {
        TujiCategory(
            id: id,
            name: name,
            nameZh: nameZh,
            emoji: "",
            description: nil,
            color: nil,
            imageUrl: nil
        )
    }

    static func collection(_ id: String) -> AtlasCollection {
        AtlasCollection(
            id: id,
            slug: "slug-\(id)",
            title: id,
            description: nil,
            targetLanguage: .ja,
            author: nil,
            itemCount: 1,
            saveCount: 0,
            avatarColor: nil,
            avatarImageUrl: nil,
            coverImageUrl: nil,
            publishedAt: nil
        )
    }

    static let categories = [
        category("kitchen", name: "Kitchen", nameZh: "廚房"),
        category("clothing", name: "Clothing", nameZh: "衣物")
    ]
}

@MainActor
private final class AssistantDictionary: LocalDictionaryReading {
    var words: [CardWord]
    init(_ words: [CardWord] = []) {
        self.words = words
    }
}

@MainActor
private final class AssistantCatalog: CategoryCatalogReading {
    var categories: [TujiCategory]
    init(_ categories: [TujiCategory] = Fixture.categories) {
        self.categories = categories
    }
}

@MainActor
private final class AssistantBookmarks: BookmarkReading {
    var favoriteIds: Set<String>
    init(_ ids: Set<String> = []) {
        self.favoriteIds = ids
    }
}

private struct ShelfUnreachable: Error {}

@MainActor
private final class AssistantShelf: CollectionBookmarking {
    var result: Result<[AtlasCollection], Error> = .success([])
    private(set) var requestedLanguages: [TargetLanguage] = []
    /// When set, `savedCollections` waits here — the slow answer a second
    /// question has to overtake.
    var gate: CheckedContinuation<Void, Never>?
    var holds = false

    func savedCollections(lang: TargetLanguage) async throws -> [AtlasCollection] {
        self.requestedLanguages.append(lang)
        if self.holds {
            await withCheckedContinuation { self.gate = $0 }
        }
        return try self.result.get()
    }

    func release() {
        self.gate?.resume()
        self.gate = nil
    }

    func collectionSaveState(slug _: String) async throws -> AtlasSaveResponse {
        AtlasSaveResponse(ok: true, saved: false, saveCount: 0)
    }

    func saveCollection(slug _: String) async throws -> AtlasSaveResponse {
        AtlasSaveResponse(ok: true, saved: true, saveCount: 1)
    }

    func unsaveCollection(slug _: String) async throws -> AtlasSaveResponse {
        AtlasSaveResponse(ok: true, saved: false, saveCount: 0)
    }
}

// MARK: - 讀懂一句話

struct AssistantIntentTests {
    private func parse(_ text: String) -> AssistantIntent? {
        AssistantIntent.parse(text, categories: Fixture.categories)
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
        (0..<count).map { Fixture.word("w\($0)", word: "pan\($0)", category: category) }
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
        self.catalog.categories = Fixture.categories + [
            Fixture.category("custom", name: "Custom", nameZh: "自製圖鑑"),
            Fixture.category("community", name: "Sightings", nameZh: "物見"),
            Fixture.category("empty", name: "Empty", nameZh: "空的")
        ]
        self.dictionary.words = [
            Fixture.word("pan", category: "kitchen"),
            Fixture.word("shirt", category: "clothing"),
            Fixture.word("atlas:mine", category: "custom"),
            Fixture.word("saved:theirs", category: "community")
        ]
        let reply = await self.responder().reply(to: .categories)
        #expect(reply.outcome == .categories)
        #expect(reply.attachment == .categories(Fixture.categories))
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
        self.dictionary.words = self.manyWords(8) + [Fixture.word("shirt", category: "clothing")]
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
            Fixture.word("contains", word: "wildcat"),
            Fixture.word("exact", word: "cat"),
            Fixture.word("miss", word: "dog")
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
        self.dictionary.words = [Fixture.word("a"), Fixture.word("b"), Fixture.word("c")]
        // `gone` is bookmarked but not in the current direction's dictionary.
        self.bookmarks.favoriteIds = ["a", "c", "gone"]
        let reply = await self.responder().reply(to: .bookmarks)
        #expect(reply.outcome == .bookmarks)
        #expect(reply.attachment == .words([Fixture.word("a"), Fixture.word("c")], total: 2, more: nil))
    }

    @Test
    func savedCardsAreTheSavedNamespaceOnly() async {
        self.dictionary.words = [
            Fixture.word("plain"),
            Fixture.word("atlas:mine"),
            Fixture.word("saved:theirs")
        ]
        let reply = await self.responder().reply(to: .savedCards)
        #expect(reply.outcome == .savedCards)
        #expect(reply.attachment == .words([Fixture.word("saved:theirs")], total: 1, more: nil))
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
        self.shelf.result = .success([Fixture.collection("one"), Fixture.collection("two")])
        let reply = await self.responder().reply(to: .savedCollections)
        #expect(reply.outcome == .collections)
        #expect(reply.attachment == .collections([Fixture.collection("one"), Fixture.collection("two")]))
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
        self.dictionary.words = [Fixture.word("hozon", word: "保存")]
        let reply = await self.responder().reply(toText: "保存")
        #expect(reply?.outcome == .favorites)
        #expect(reply?.suggestions.first == .lookup(query: "保存"))
    }

    @Test
    func aPlainLookupDoesNotOfferItselfAgain() async {
        self.dictionary.words = [Fixture.word("cat")]
        let reply = await self.responder().reply(toText: "cat")
        #expect(reply?.outcome == .words)
        #expect(reply?.suggestions.isEmpty == true)
    }
}

// MARK: - 對話

@MainActor
struct AssistantChatModelTests {
    private let dictionary = AssistantDictionary([Fixture.word("cat")])
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
        self.shelf.result = .success([Fixture.collection("one")])
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
