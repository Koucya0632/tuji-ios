// 今天's scene card and the 圖鑑 → 場面 links, against small scenes built here.

import Foundation
import Testing
@testable import Tuji

private nonisolated enum Build {
    static func question(_ id: String, words: [String]) -> String {
        let phrasing = { (suffix: String, role: String, fast: Bool) in
            """
            {"id":"\(id).\(suffix)","role":"\(role)","speaker":"clerk","text":"温めますか？","voice":"Aoede",
             "speed":"\(fast ? "fast" : "normal")","ambience":\(fast),"screen":null,"audio":"\(id).\(suffix).mp3"}
            """
        }
        let ids = words.map { "\"\($0)\"" }.joined(separator: ",")
        return """
        {"id":"\(id)","kind":"listening","goal":{"zh-Hant":"g","zh-Hans":"g","en":"g"},
         "phrasings":[\(phrasing("p1", "first", false)),\(phrasing("p2", "review", false)),\(phrasing(
             "p3",
             "review",
             true
         ))],
         "choices":[{"id":"a","text":{"zh-Hant":"a","zh-Hans":"a","en":"a"},"correct":true},
                    {"id":"b","text":{"zh-Hant":"b","zh-Hans":"b","en":"b"},"correct":false},
                    {"id":"c","text":{"zh-Hant":"c","zh-Hans":"c","en":"c"},"correct":false}],
         "response":{"ja":"はい","audio":null,"voice":null},
         "explanation":{"zh-Hant":"e","zh-Hans":"e","en":"e"},
         "wordIds":[\(ids)]}
        """
    }

    /// `words[i]` are the word ids question `i` references.
    static func scene(_ id: String, access: String = "free", words: [[String]] = [[], []]) -> PracticeScene {
        let questions = words.enumerated().map { self.question("\(id).q\($0.offset)", words: $0.element) }
        let json = """
        {"schemaVersion":2,"id":"\(id)","revision":1,"access":"\(access)",
         "title":{"zh-Hant":"t","zh-Hans":"t","en":"t"},"summary":{"zh-Hant":"s","zh-Hans":"s","en":"s"},
         "questions":[\(questions.joined(separator: ","))]}
        """
        do {
            return try JSONDecoder().decode(PracticeScene.self, from: Data(json.utf8))
        } catch {
            preconditionFailure("fixture scene does not decode: \(error)")
        }
    }

    static let today = LocalDay(year: 2026, month: 11, day: 9)
    static let yesterday = LocalDay(year: 2026, month: 11, day: 8)
}

struct SceneCardPickTests {
    private let konbini = Build.scene("konbini")
    private let restaurant = Build.scene("restaurant")
    private let hotel = Build.scene("hotel", access: "lifetime")

    private func pick(_ book: SceneProgressBook, member: Bool = false) -> SceneCardPick? {
        SceneCards.pick(
            [self.konbini, self.restaurant, self.hotel],
            book: book,
            today: Build.today,
            canPractise: { $0.canPractise(member ? .lifetime : .free) }
        )
    }

    private func id(_ raw: String) -> SceneQuestionID {
        SceneQuestionID(rawValue: raw)
    }

    @Test
    func aNewAccountIsOfferedTheFirstScene() {
        let pick = self.pick(SceneProgressBook())
        #expect(pick?.scene.id == self.konbini.id)
        #expect(pick?.state == .notStarted)
    }

    @Test
    func aReviewDueTodayComesBeforeAHalfDoneScene() {
        var book = SceneProgressBook()
        book.questions[self.id("restaurant.q0")] = QuestionProgress(stage: .awaitingReview(due: Build.today))
        book.questions[self.id("restaurant.q1")] = QuestionProgress(stage: .awaitingReview(due: Build.today))
        book.questions[self.id("konbini.q0")] = QuestionProgress(stage: .awaitingReview(due: Build.today.adding(
            days: 1,
            calendar: .current
        )))
        #expect(self.pick(book)?.scene.id == self.restaurant.id)
        #expect(self.pick(book)?.state == .reviewDue)
    }

    @Test
    func aHalfDoneSceneReopensOnTheQuestionPracticeStoppedAt() {
        var book = SceneProgressBook()
        book.questions[self.id("restaurant.q0")] = QuestionProgress(stage: .awaitingReview(due: Build.today.adding(
            days: 1,
            calendar: .current
        )))
        book.cursors[self.restaurant.id] = 1
        let pick = self.pick(book)
        #expect(pick?.scene.id == self.restaurant.id)
        #expect(pick?.state == .inProgress(at: 2))
        #expect(pick?.practised == [true, false])
    }

    @Test
    func aNonMemberIsNeverOfferedAMembersScene() {
        var book = SceneProgressBook()
        for scene in [self.konbini, self.restaurant] {
            for question in scene.questions {
                book.questions[question.id] = QuestionProgress(stage: .reviewed)
            }
        }
        book.lastSceneId = self.restaurant.id
        #expect(self.pick(book)?.scene.id == self.restaurant.id)
        #expect(self.pick(book)?.state == .allDone(.complete))
        #expect(self.pick(book, member: true)?.scene.id == self.hotel.id)
        #expect(self.pick(book, member: true)?.state == .notStarted)
    }
}

struct SceneLinksTests {
    private let catalog = SceneCatalog(scenes: [
        Build.scene("konbini", words: [["point-card", "receipt"], ["plastic-bag"]]),
        Build.scene("restaurant", words: [["menu"], ["receipt"]]),
        Build.scene("drugstore", words: [["receipt"], []])
    ])

    @Test
    func aWordListsTheQuestionsThatAskAboutItGroupedByScene() {
        let mentions = SceneLinks.mentions(of: "receipt", in: self.catalog, excluding: nil)
        #expect(mentions.map(\.scene.id.rawValue) == ["konbini", "restaurant", "drugstore"])
        #expect(mentions[1].questions.map(\.id.rawValue) == ["restaurant.q1"])
    }

    @Test
    func aWordPageOpenedFromASceneLeavesThatSceneOut() {
        let mentions = SceneLinks.mentions(of: "receipt", in: self.catalog, excluding: SceneID(rawValue: "konbini"))
        #expect(mentions.map(\.scene.id.rawValue) == ["restaurant", "drugstore"])
    }

    @Test
    func aTopicListsAtMostTwoScenesThoseUsingMostOfItsWordsFirst() {
        let topicOf = [
            "point-card": "convenience-store",
            "plastic-bag": "supermarket",
            "receipt": "supermarket",
            "menu": "restaurant"
        ]
        let scenes = SceneLinks.scenes(forTopic: "supermarket", topicOf: topicOf, in: self.catalog)
        #expect(scenes.map(\.id.rawValue) == ["konbini", "restaurant"])
        #expect(SceneLinks.scenes(forTopic: "restaurant", topicOf: topicOf, in: self.catalog)
            .map(\.id.rawValue) == ["restaurant"])
        #expect(SceneLinks.scenes(forTopic: "fruits", topicOf: topicOf, in: self.catalog).isEmpty)
    }
}

struct SceneIndexTests {
    @Test
    func releasedScenesAreGroupedAndFree() throws {
        let index = try SceneCatalog.index(bundle: .main)
        let catalog = try SceneCatalog.load(bundle: .main)
        #expect(!index.released.isEmpty)
        for id in index.released {
            #expect(index.ids.contains(id), "\(id.rawValue)")
            #expect(catalog.scene(id)?.access == .free, "\(id.rawValue)")
        }
        #expect(Set(index.groups.map(\.id)).count == index.groups.count)
    }
}
