// 跟著 Moira 去旅遊: what the server's answer decodes to, what each screen
// decides from it, and what the two requests look like.
//
// THE RED LINES:
//   - A map shape this build does not know is dropped, not fatal: the server
//     adds shapes without waiting for an app release.
//   - A non-member studies a free spot and meets the paywall at any other;
//     an account that is not gated meets it nowhere.
//   - A study mode with nothing in it is never offered.
//   - The entry is drawn exactly when the server names somewhere to go.

import CoreGraphics
import Foundation
import Testing
@testable import Tuji

@MainActor
struct TravelTests {
    private static let json = """
    {"destinations":[{"id":"japan","name":"日本","grid":{"columns":14,"rows":16},
      "regions":[
        {"id":"kanto","name":"關東","tiles":[[9,7],[10,7]],"nameAt":[11.8,7.5],"cityIds":["tokyo"]},
        {"id":"kansai","name":"關西","tiles":[[5,9]],"nameAt":[8.8,10.6],"cityIds":[]}],
      "cities":[{"id":"tokyo","name":"東京","regionId":"kanto","aspect":1.4444,
        "shapes":[
          {"kind":"water","points":[[0.6,1],[1,0.8],[1,1]],"name":"東京灣","nameAt":[0.88,0.92]},
          {"kind":"ring","center":[0.45,0.5],"radius":[0.2,0.33],"name":"山手線","nameAt":[0.45,0.5]},
          {"kind":"monorail","points":[[0,0]],"name":"?","nameAt":[0,0]}],
        "spots":[
          {"id":"akihabara","name":"秋葉原","native":"秋葉原","reading":"あきはばら","at":[0.636,0.389],
           "label":"right","wordIds":["claw-machine","pin-badge","trading-card"],"open":true,"free":true},
          {"id":"asakusa","name":"淺草","native":"浅草","reading":"あさくさ","at":[0.733,0.193],
           "label":"right","wordIds":["paper-lantern","fortune-slip"],"open":false,"free":false}]}]}]}
    """

    private var destination: TravelDestination {
        get throws {
            let response = try JSONDecoder().decode(TravelResponse.self, from: Data(Self.json.utf8))
            return try #require(response.destinations.first)
        }
    }

    private func spot(_ id: String) throws -> TravelSpot {
        try #require(try self.destination.cities.flatMap(\.spots).first { $0.id == id })
    }

    private func word(_ id: String, _ category: String = "collecting-hobbies") -> CardWord {
        CardWord(id: id, word: id, chinese: id, imageUrl: "", category: category, pronunciation: "")
    }

    // MARK: Decoding

    @Test
    func decodesPointsFromPairs() throws {
        let akihabara = try self.spot("akihabara")
        #expect(akihabara.at == TravelPoint(x: 0.636, y: 0.389))
        #expect(akihabara.label == .right)
        #expect(try self.destination.regions[0].tiles == [TravelPoint(x: 9, y: 7), TravelPoint(x: 10, y: 7)])
    }

    @Test
    func dropsAShapeItDoesNotKnowAndKeepsTheRest() throws {
        let shapes = try #require(try self.destination.city("tokyo")).shapes
        #expect(shapes.map(\.name) == ["東京灣", "山手線"])
    }

    @Test
    func aRegionListsOnlyCitiesWithSomethingOpen() throws {
        let destination = try self.destination
        #expect(destination.openCities(in: destination.regions[0]).map(\.id) == ["tokyo"])
        #expect(destination.openCities(in: destination.regions[1]).isEmpty)
        #expect(TravelDecisions.openSpotCount(destination) == 1)
    }

    // MARK: The 2026-11 maps

    private static let mapJSON = """
    {"destinations":[{"id":"japan","name":"日本","grid":{"columns":14,"rows":16},
      "map":{"aspect":0.7617,"coast":[[[0.1,0.1],[0.2,0.1],[0.2,0.2]]],
        "frames":[{"at":[0.03,0.03],"size":[0.23,0.21]}],"seas":[{"name":"太平洋","at":[0.5,0.7]}]},
      "regions":[
        {"id":"kanto","name":"關東","tiles":[[9,7]],"nameAt":[11.8,7.5],"cityIds":["tokyo"],
         "tone":2,"shapes":[[[0.6,0.6],[0.7,0.6],[0.7,0.7]]],"labelAt":[0.62,0.6],
         "card":{"at":[0.73,0.57],"width":0.25,"pointAt":[0.64,0.6],"lines":["東京  日光"]}},
        {"id":"chubu","name":"中部","tiles":[[8,6]],"nameAt":[5.8,7.5],"cityIds":[],
         "tone":3,"shapes":[[[0.4,0.5],[0.5,0.5],[0.5,0.6]]],"labelAt":[0.49,0.59]}],
      "cities":[{"id":"tokyo","name":"東京","regionId":"kanto","aspect":1.04,"mapAt":[0.62,0.62],"shapes":[],
        "spots":[
          {"id":"asakusa","name":"淺草","native":"浅草","reading":"あさくさ","at":[0.76,0.08],"label":"right",
           "wordIds":["paper-lantern"],"open":true,"free":false,"pin":[0.75,0.1],"tag":[0.75,0.2]},
          {"id":"ueno","name":"上野","native":"上野","reading":"うえの","at":[0.5,0.15],"label":"left",
           "wordIds":["park"],"open":true,"free":true,"pin":[0.6,0.1],"tag":[0.6,0.3],"tagShort":true}]}]}]}
    """

    private var mapped: TravelDestination {
        get throws {
            let response = try JSONDecoder().decode(TravelResponse.self, from: Data(Self.mapJSON.utf8))
            return try #require(response.destinations.first)
        }
    }

    @Test
    func decodesTheOutlineCardsAndTags() throws {
        let japan = try self.mapped
        let outline = try #require(japan.outline)
        #expect(outline.coast.first?.count == 3)
        #expect(outline.seas.map(\.name) == ["太平洋"])
        let kanto = try #require(japan.region("kanto"))
        #expect(kanto.tone == 2)
        #expect(kanto.card?.lines == ["東京  日光"])
        #expect(japan.region("chubu")?.card == nil)
        let tokyo = try #require(japan.city("tokyo"))
        #expect(tokyo.mapAt == TravelPoint(x: 0.62, y: 0.62))
        #expect(tokyo.hasTaggedMap)
        #expect(tokyo.spots[1].tagShort == true)
        #expect(tokyo.spots[0].tagShort == nil)
    }

    @Test
    func anOlderAnswerDrawsTheGridAndTheNudgedSpots() throws {
        let japan = try self.destination
        #expect(japan.map == nil)
        #expect(japan.outline == nil)
        #expect(try #require(japan.city("tokyo")).hasTaggedMap == false)
    }

    @Test
    func theOutlineIsDrawnOnlyWhenEveryRegionHasItsArea() throws {
        let json = Self.mapJSON.replacingOccurrences(
            of: #""tone":3,"shapes":[[[0.4,0.5],[0.5,0.5],[0.5,0.6]]],"#,
            with: ""
        )
        let response = try JSONDecoder().decode(TravelResponse.self, from: Data(json.utf8))
        let japan = try #require(response.destinations.first)
        #expect(japan.map != nil)
        #expect(japan.outline == nil)
    }

    @Test
    func aCardIsAsTallAsItsLines() {
        #expect(TravelDecisions.cardHeight(lines: 1) == 56)
        #expect(TravelDecisions.cardHeight(lines: 2) == 74)
    }

    @Test
    func aCityRowNamesItsOpenSpots() throws {
        let tokyo = try #require(try self.mapped.city("tokyo"))
        #expect(TravelDecisions.spotPreview(tokyo) == "淺草、上野")
        #expect(TravelDecisions.listSeparator(["Asakusa", "Ueno"]) == ", ")
        #expect(TravelDecisions.stampMark("由布院") == "由")
    }

    @Test
    func regionsWithNothingOpenShareOneRow() throws {
        #expect(try TravelDecisions.closedRegions(self.mapped).map(\.id) == ["chubu"])
    }

    // MARK: Access

    @Test
    func aNonMemberStudiesTheFreeSpotOnly() throws {
        let gated = ["fruits", "bedroom"]
        #expect(try TravelDecisions.access(to: self.spot("akihabara"), studyable: gated) == .open)
        #expect(try TravelDecisions.access(to: self.spot("asakusa"), studyable: gated) == .needsMembership)
    }

    @Test
    func anAccountThatIsNotGatedStudiesEverySpot() throws {
        #expect(try TravelDecisions.access(to: self.spot("asakusa"), studyable: nil) == .open)
    }

    // MARK: Spot state

    @Test
    func countsStudiedAndDueAmongTheWordsTheDictionaryHas() throws {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let state = try TravelDecisions.state(
            of: self.spot("akihabara"),
            // `trading-card` has not loaded; `banana` is not the spot's.
            words: [self.word("pin-badge"), self.word("banana", "fruits"), self.word("claw-machine")],
            scores: ["claw-machine": 40, "pin-badge": 10, "trading-card": 90, "banana": 5],
            nextReview: ["claw-machine": now.addingTimeInterval(-60), "pin-badge": now.addingTimeInterval(60)],
            studyable: nil,
            now: now
        )
        // The spot's order, not the dictionary's.
        #expect(state.words.map(\.id) == ["claw-machine", "pin-badge"])
        #expect(state.studied == 2)
        #expect(state.due == 1)
        #expect(state.progress == 1)
        // Nothing new is left, one is due.
        #expect(state.studyModes == [.review])
    }

    @Test
    func offersOnlyModesWithSomethingInThem() throws {
        let spot = try self.spot("akihabara")
        let words = spot.wordIds.map { self.word($0) }
        func modes(scores: [String: Int], due: [String: Date] = [:], studyable: [String]? = nil) -> [StudyMode] {
            TravelDecisions.state(
                of: spot, words: words, scores: scores, nextReview: due, studyable: studyable,
                now: Date(timeIntervalSince1970: 100)
            ).studyModes
        }
        #expect(modes(scores: [:]) == [.new])
        #expect(modes(scores: ["pin-badge": 1], due: ["pin-badge": Date(timeIntervalSince1970: 0)]) == [.new, .review])
        let all = Dictionary(uniqueKeysWithValues: spot.wordIds.map { ($0, 50) })
        #expect(modes(scores: all).isEmpty)
    }

    @Test
    func aLockedSpotOffersNoModeHoweverMuchIsLeft() throws {
        let spot = try self.spot("asakusa")
        let state = TravelDecisions.state(
            of: spot, words: spot.wordIds.map { self.word($0, "festivals") },
            scores: [:], nextReview: [:], studyable: ["fruits"]
        )
        #expect(state.access == .needsMembership)
        #expect(state.studyModes.isEmpty)
    }

    @Test
    func aSpotWithNoWordsLoadedIsEmptyNotComplete() throws {
        let state = try TravelDecisions.state(
            of: self.spot("akihabara"), words: [], scores: [:], nextReview: [:], studyable: nil
        )
        #expect(state.total == 0)
        #expect(state.progress == 0)
        #expect(state.studyModes.isEmpty)
    }

    // MARK: Entry and grid

    @Test
    func theEntryShowsOnlyWhenThereIsSomewhereToGo() throws {
        #expect(!TravelDecisions.showsEntry([]))
        #expect(try TravelDecisions.showsEntry([self.destination]))
    }

    @Test
    func cellsFillTheWidthWithGapsBetween() {
        let side = TravelDecisions.cellSide(width: 362, columns: 14, gap: 2)
        #expect(side == 24)
        #expect(TravelDecisions.cellOrigin(TravelPoint(x: 13, y: 2), side: side, gap: 2) == CGPoint(x: 338, y: 52))
        #expect(TravelDecisions.cellSide(width: 100, columns: 0, gap: 2) == 0)
    }

    // MARK: Requests

    @Test
    func theMapIsPublicAndScopedByBothLanguages() {
        let descriptor = Endpoint.travel(lang: "zh-Hant", learning: "zh-ja").travelDescriptor
        #expect(descriptor.path == "/api/travel")
        #expect(descriptor.queryItems.map(\.name) == ["lang", "learning"])
        #expect(descriptor.policy.access != .authenticated)
    }

    @Test
    func aSpotQueueNamesTheSpotAndIsThePersonsOwn() {
        let descriptor = Endpoint
            .studySpotQueue(spotId: "akihabara", mode: "new", limit: 30, lang: "zh-Hant", learning: "zh-ja")
            .travelDescriptor
        #expect(descriptor.path == "/api/study/queue")
        #expect(descriptor.queryItems.first { $0.name == "spot" }?.value == "akihabara")
        #expect(!descriptor.queryItems.contains { $0.name == "category" || $0.name == "list" })
        #expect(descriptor.policy.access == .authenticated)
        #expect(descriptor.policy.cachePolicy == .reloadIgnoringLocalCacheData)
    }

    // MARK: Store

    private final class FakeRepository: TravelRepository {
        var answers: [String: Result<TravelResponse, Error>] = [:]
        private(set) var asked: [String] = []

        func destinations(lang: String, learning: String) async throws -> TravelResponse {
            self.asked.append("\(lang)|\(learning)")
            return try (self.answers[learning] ?? .success(TravelResponse(destinations: []))).get()
        }

        func queue(spotId _: String, mode _: StudyMode, limit _: Int) async throws -> StudyQueueResponse {
            throw URLError(.unsupportedURL)
        }
    }

    private struct Languages: LanguageContext {
        var uiLang = "zh-Hant"
        var learningDirection: LearningDirection = .zhJa
    }

    @Test
    func loadsOncePerLanguagePairAndAgainWhenItChanges() async throws {
        let repository = FakeRepository()
        repository.answers["zh-ja"] = try .success(TravelResponse(destinations: [self.destination]))
        let store = TravelStore(repository: repository)

        await store.loadIfNeeded(settings: Languages())
        await store.loadIfNeeded(settings: Languages())
        #expect(repository.asked.count == 1)
        #expect(store.spot("akihabara")?.name == "秋葉原")
        #expect(store.city("tokyo", in: "japan")?.spots.count == 2)

        // 英文: the server answers nothing, which is an answer — the entry goes.
        await store.loadIfNeeded(settings: Languages(learningDirection: .zhEn))
        #expect(repository.asked.count == 2)
        #expect(store.destinations.isEmpty)
        #expect(store.phase == .loaded)
    }

    @Test
    func aFailedFirstLoadIsAskedAgain() async throws {
        let repository = FakeRepository()
        repository.answers["zh-ja"] = .failure(URLError(.notConnectedToInternet))
        let store = TravelStore(repository: repository)

        await store.loadIfNeeded(settings: Languages())
        #expect(store.phase == .failed)

        repository.answers["zh-ja"] = try .success(TravelResponse(destinations: [self.destination]))
        await store.loadIfNeeded(settings: Languages())
        #expect(store.phase == .loaded)
        #expect(store.destinations.count == 1)
    }
}
