// Pins which source a word id is loaded from, and what stays on screen when
// the load fails.
//
// The routing lived inside a `private func` on `WordDetailPage`, whose
// repository was a hardcoded `.shared` with no init seam and which reached
// `AtlasStore.shared` and `SettingsStore.shared` from inside itself — the last
// of those despite the screen already having `SettingsStore` injected and
// unused. So none of these rules had a test, including the one that decides
// whether 自製圖鑑 content reaches analytics.

import Foundation
import Testing
@testable import Tuji

@MainActor
struct WordDetailVMTests {
    private func lite(_ id: String, category: String = "kitchen", detail: Word? = nil) -> CardWord {
        CardWord(
            id: id,
            word: "cup",
            chinese: "杯子",
            imageUrl: "https://example.com/i.jpg",
            category: category,
            pronunciation: "kʌp",
            detail: detail
        )
    }

    private func full(_ id: String, word: String) -> Word {
        WordDetailVM.provisionalWord(
            from: self.lite(id),
            tags: []
        ).replacing(word: word)
    }

    @Test("a catalogue id goes to the catalogue, never to the atlas")
    func publicIdRoutesToCatalogue() async {
        let catalog = FakeCatalog(word: self.full("w1", word: "full cup"))
        let atlas = FakeAtlasDetail()
        let vm = WordDetailVM(catalog: catalog, atlas: atlas, words: FakeLookup())

        await vm.load(id: "w1", lang: "zh-Hant", learning: "en")

        #expect(catalog.requested == ["w1"])
        #expect(atlas.requested.isEmpty)
    }

    @Test("an atlas id goes to the atlas with the prefix stripped")
    func atlasIdRoutesToAtlas() async {
        let catalog = FakeCatalog(word: self.full("x", word: "x"))
        let atlas = FakeAtlasDetail(word: self.full("uuid-1", word: "my photo"))
        let vm = WordDetailVM(catalog: catalog, atlas: atlas, words: FakeLookup())

        await vm.load(id: "atlas:uuid-1", lang: "zh-Hant", learning: "en")

        #expect(atlas.requested == ["uuid-1"])
        #expect(catalog.requested.isEmpty)
        #expect(vm.word?.word == "my photo")
    }

    @Test("自製圖鑑 is never logged as a page view")
    func atlasContentIsNotTracked() async {
        // The VM returns the word worth logging; private content returns nil so
        // the View has nothing to track.
        let atlas = FakeAtlasDetail(word: self.full("uuid-1", word: "my photo"))
        let vm = WordDetailVM(catalog: FakeCatalog(), atlas: atlas, words: FakeLookup())

        let logged = await vm.load(id: "atlas:uuid-1", lang: "zh-Hant", learning: "en")

        #expect(logged == nil)
    }

    @Test("an embedded detail renders without a second round-trip")
    func embeddedDetailSkipsTheNetwork() async {
        let embedded = self.full("atlas:uuid-1", word: "already enriched")
        let lookup = FakeLookup(word: self.lite("atlas:uuid-1", category: "custom", detail: embedded))
        let atlas = FakeAtlasDetail()
        let vm = WordDetailVM(catalog: FakeCatalog(), atlas: atlas, words: lookup)

        await vm.load(id: "atlas:uuid-1", lang: "zh-Hant", learning: "en")

        #expect(vm.word?.word == "already enriched")
        #expect(atlas.requested.isEmpty, "the embedded payload is the whole point")
    }

    @Test("the grid's lite payload renders before the full one arrives")
    func provisionalRendersFirst() async {
        let lookup = FakeLookup(word: self.lite("w1"))
        let vm = WordDetailVM(catalog: FakeCatalog(), atlas: FakeAtlasDetail(), words: lookup)

        await vm.load(id: "w1", lang: "zh-Hant", learning: "en")

        // FakeCatalog with no word throws, so what remains on screen is the
        // provisional card — which is exactly the rule below.
        #expect(vm.word != nil)
    }

    @Test("a late failure does not blank a page that already has content")
    func lateFailureKeepsTheProvisionalCard() async {
        let lookup = FakeLookup(word: self.lite("w1"))
        let catalog = FakeCatalog()
        catalog.result = .failure(WordFakeError.boom)
        let vm = WordDetailVM(catalog: catalog, atlas: FakeAtlasDetail(), words: lookup)

        await vm.load(id: "w1", lang: "zh-Hant", learning: "en")

        #expect(vm.word != nil, "the provisional card must survive")
        #expect(vm.error == nil, "an error state would replace readable content")
    }

    @Test("a failure with nothing on screen surfaces the error")
    func failureWithNoContentSurfacesError() async {
        let catalog = FakeCatalog()
        catalog.result = .failure(WordFakeError.boom)
        let vm = WordDetailVM(catalog: catalog, atlas: FakeAtlasDetail(), words: FakeLookup())

        await vm.load(id: "w1", lang: "zh-Hant", learning: "en")

        #expect(vm.word == nil)
        #expect(vm.error != nil)
    }

    @Test("a second load is a no-op once the word is in hand")
    func loadIsIdempotent() async {
        let catalog = FakeCatalog(word: self.full("w1", word: "full cup"))
        let vm = WordDetailVM(catalog: catalog, atlas: FakeAtlasDetail(), words: FakeLookup())

        await vm.load(id: "w1", lang: "zh-Hant", learning: "en")
        await vm.load(id: "w1", lang: "zh-Hant", learning: "en")

        #expect(catalog.requested == ["w1"])
    }

    @Test("the language pair reaches the catalogue call")
    func languageIsForwarded() async {
        let catalog = FakeCatalog(word: self.full("w1", word: "full cup"))
        let vm = WordDetailVM(catalog: catalog, atlas: FakeAtlasDetail(), words: FakeLookup())

        await vm.load(id: "w1", lang: "ja", learning: "en")

        #expect(catalog.lastLang == "ja")
        #expect(catalog.lastLearning == "en")
    }
}

private enum WordFakeError: Error { case boom }

private extension Word {
    /// Minimal copy helper so fixtures can vary one field.
    func replacing(word: String) -> Word {
        Word(
            id: self.id,
            word: word,
            alsoKnownAs: self.alsoKnownAs,
            category: self.category,
            partOfSpeech: self.partOfSpeech,
            pronunciation: self.pronunciation,
            reading: self.reading,
            targetLanguage: self.targetLanguage,
            audioUrl: self.audioUrl,
            audioUrls: self.audioUrls,
            imageUrl: self.imageUrl,
            cefrLevel: self.cefrLevel,
            status: self.status,
            chinese: self.chinese,
            definitions: self.definitions,
            examples: self.examples,
            relations: self.relations,
            collocations: self.collocations,
            collocationsZh: self.collocationsZh,
            note: self.note,
            etymology: self.etymology,
            forms: self.forms,
            chineseDefinition: self.chineseDefinition,
            targetDefinition: self.targetDefinition,
            englishDefinition: self.englishDefinition,
            tags: self.tags
        )
    }
}

@MainActor
private final class FakeLookup: WordLookup {
    private let word: CardWord?
    init(word: CardWord? = nil) {
        self.word = word
    }

    func find(id _: String) -> CardWord? {
        self.word
    }
}

@MainActor
private final class FakeAtlasDetail: AtlasItemDetailReading {
    private let word: Word?
    private(set) var requested: [String] = []
    init(word: Word? = nil) {
        self.word = word
    }

    func detail(itemId: String) async throws -> Word {
        self.requested.append(itemId)
        guard let word else { throw WordFakeError.boom }
        return word
    }
}

@MainActor
private final class FakeCatalog: WordReading {
    var result: Result<Word, Error>
    private(set) var requested: [String] = []
    private(set) var lastLang: String?
    private(set) var lastLearning: String?

    init(word: Word? = nil) {
        self.result = word.map { .success($0) } ?? .failure(WordFakeError.boom)
    }

    func word(id: String, lang: String, learning: String) async throws -> Word {
        self.requested.append(id)
        self.lastLang = lang
        self.lastLearning = learning
        return try self.result.get()
    }
}
