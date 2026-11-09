// 場面練習's scheduling, phrasing choice, per-account progress and resume.

import Foundation
import Testing
@testable import Tuji

private nonisolated enum Fixture {
    /// UTC+8, so "the next local day" is checked against a real offset.
    static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 8 * 3600) ?? .current
        return calendar
    }()

    static func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        self.calendar
            .date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute)) ?? .distantPast
    }

    static func phrasing(_ id: String, role: String, speed: String = "normal", ambience: Bool = false) -> String {
        """
        {"id":"\(id)","role":"\(role)","speaker":"clerk","text":"温めますか？","voice":"Aoede",
         "speed":"\(speed)","ambience":\(ambience),"screen":null,"audio":"\(id).mp3"}
        """
    }

    static func question(_ id: String) -> String {
        """
        {"id":"\(id)","kind":"listening",
         "goal":{"zh-Hant":"g","zh-Hans":"g","en":"g"},
         "phrasings":[
           \(self.phrasing("\(id).p1", role: "first")),
           \(self.phrasing("\(id).p2", role: "review")),
           \(self.phrasing("\(id).p3", role: "review", speed: "fast", ambience: true)),
           \(self.phrasing("\(id).p4", role: "review"))
         ],
         "choices":[
           {"id":"a","text":{"zh-Hant":"a","zh-Hans":"a","en":"a"},"correct":true},
           {"id":"b","text":{"zh-Hant":"b","zh-Hans":"b","en":"b"},"correct":false},
           {"id":"c","text":{"zh-Hant":"c","zh-Hans":"c","en":"c"},"correct":false}
         ],
         "response":{"ja":"お願いします","audio":null,"voice":null},
         "explanation":{"zh-Hant":"e","zh-Hans":"e","en":"e"},
         "wordIds":[]}
        """
    }

    static let scene: PracticeScene = {
        let json = """
        {"schemaVersion":2,"id":"s","revision":1,"access":"free",
         "title":{"zh-Hant":"t","zh-Hans":"t","en":"t"},
         "summary":{"zh-Hant":"s","zh-Hans":"s","en":"s"},
         "questions":[\(["s.q0", "s.q1", "s.q2"].map(question).joined(separator: ","))]}
        """
        do {
            return try JSONDecoder().decode(PracticeScene.self, from: Data(json.utf8))
        } catch {
            preconditionFailure("fixture scene does not decode: \(error)")
        }
    }()

    static func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(
            "scene-tests-\(UUID().uuidString)",
            isDirectory: true
        )
    }
}

struct ScenePhrasingSelectionTests {
    private let question = Fixture.scene.questions[0]

    @Test
    func firstPracticeUsesTheFirstPhrasing() {
        let picked = ScenePractice.phrasing(for: self.question, progress: QuestionProgress(), mode: .first)
        #expect(picked?.id.rawValue == "s.q0.p1")
    }

    @Test
    func aReviewTakesTheFastAmbiencePhrasingFirst() {
        let progress = QuestionProgress(
            stage: .awaitingReview(due: LocalDay(year: 2026, month: 11, day: 9)),
            usedPhrasingIds: [PhrasingID(rawValue: "s.q0.p1")]
        )
        let picked = ScenePractice.phrasing(for: self.question, progress: progress, mode: .review)
        #expect(picked?.id.rawValue == "s.q0.p3")
    }

    @Test
    func aReviewNeverRepeatsAPhrasingThisAccountHasHeard() {
        let used: Set<PhrasingID> = ["s.q0.p1", "s.q0.p3"].map(PhrasingID.init(rawValue:))
            .reduce(into: []) { $0.insert($1) }
        let progress = QuestionProgress(stage: .reviewed, usedPhrasingIds: used)
        #expect(ScenePractice.phrasing(for: self.question, progress: progress, mode: .review)?.id.rawValue == "s.q0.p2")
    }

    @Test
    func rehearsingBeforeTheReviewIsDueDoesNotSpendAReviewPhrasing() {
        let progress = QuestionProgress(stage: .awaitingReview(due: LocalDay(year: 2026, month: 11, day: 9)))
        #expect(ScenePractice.phrasing(for: self.question, progress: progress, mode: .rehearsal)?.id
            .rawValue == "s.q0.p1")
    }
}

struct SceneSchedulingTests {
    private let calendar = Fixture.calendar

    @Test
    func aReviewIsDueOnTheNextLocalDayNotTwentyFourHoursLater() throws {
        let lateNight = Fixture.date(2026, 11, 8, 23, 50)
        let today = LocalDay(lateNight, calendar: self.calendar)
        let step = try #require(ScenePractice.plan(Fixture.scene, book: SceneProgressBook(), today: today).first)

        let after = ScenePractice.completing(QuestionProgress(), step: step, today: today, calendar: self.calendar)

        #expect(after.stage == .awaitingReview(due: LocalDay(year: 2026, month: 11, day: 9)))
        #expect(after.usedPhrasingIds == [step.phrasing.id])
        #expect(ScenePractice.mode(for: after, today: today) == .rehearsal)
        let tenMinutesLater = LocalDay(Fixture.date(2026, 11, 9, 0, 0), calendar: self.calendar)
        #expect(ScenePractice.mode(for: after, today: tenMinutesLater) == .review)
    }

    @Test
    func theNextDayRollsOverMonthAndYearEnds() {
        #expect(LocalDay(year: 2026, month: 1, day: 31).adding(days: 1, calendar: self.calendar) == LocalDay(
            year: 2026,
            month: 2,
            day: 1
        ))
        #expect(LocalDay(year: 2026, month: 12, day: 31).adding(days: 1, calendar: self.calendar) == LocalDay(
            year: 2027,
            month: 1,
            day: 1
        ))
    }

    @Test
    func anOverdueReviewIsStillDue() {
        let progress = QuestionProgress(stage: .awaitingReview(due: LocalDay(year: 2026, month: 11, day: 9)))
        #expect(ScenePractice.mode(for: progress, today: LocalDay(year: 2026, month: 11, day: 20)) == .review)
    }

    @Test
    func aReviewMovesTheQuestionToReviewed() throws {
        let progress = QuestionProgress(
            stage: .awaitingReview(due: LocalDay(year: 2026, month: 11, day: 9)),
            usedPhrasingIds: [PhrasingID(rawValue: "s.q0.p1")]
        )
        let phrasing = try #require(Fixture.scene.questions[0].phrasing(PhrasingID(rawValue: "s.q0.p3")))
        let step = PracticeStep(questionIndex: 0, mode: .review, phrasing: phrasing)

        let after = ScenePractice.completing(
            progress,
            step: step,
            today: LocalDay(year: 2026, month: 11, day: 9),
            calendar: self.calendar
        )

        #expect(after.stage == .reviewed)
        #expect(after.usedPhrasingIds.count == 2)
    }

    @Test
    func thePlanHoldsOnlyWhatIsOwedAndStartsAtTheCursor() {
        let today = LocalDay(year: 2026, month: 11, day: 9)
        var book = SceneProgressBook()
        book.questions[SceneQuestionID(rawValue: "s.q0")] = QuestionProgress(stage: .awaitingReview(due: LocalDay(
            year: 2026,
            month: 11,
            day: 10
        )))
        book.cursors[SceneID(rawValue: "s")] = 2

        let plan = ScenePractice.plan(Fixture.scene, book: book, today: today)

        #expect(plan.map(\.questionIndex) == [2, 1])
        #expect(plan.allSatisfy { $0.mode == .first })
    }

    @Test
    func withNothingOwedTheWholeSceneIsARehearsal() {
        var book = SceneProgressBook()
        for question in Fixture.scene.questions {
            book.questions[question.id] = QuestionProgress(stage: .reviewed)
        }
        let plan = ScenePractice.plan(Fixture.scene, book: book, today: LocalDay(year: 2026, month: 11, day: 9))
        #expect(plan.map(\.questionIndex) == [0, 1, 2])
        #expect(plan.allSatisfy { $0.mode == .rehearsal })
    }

    @Test
    func theStatusSaysWhatTheSceneListShows() {
        let today = LocalDay(year: 2026, month: 11, day: 9)
        let tomorrow = LocalDay(year: 2026, month: 11, day: 10)
        let ids = Fixture.scene.questions.map(\.id)
        var book = SceneProgressBook()
        #expect(ScenePractice.status(Fixture.scene, book: book, today: today) == .notStarted)

        book.questions[ids[0]] = QuestionProgress(stage: .awaitingReview(due: tomorrow))
        #expect(ScenePractice.status(Fixture.scene, book: book, today: today) == .inProgress(practised: 1, total: 3))

        book.questions[ids[1]] = QuestionProgress(stage: .awaitingReview(due: tomorrow))
        book.questions[ids[2]] = QuestionProgress(stage: .reviewed)
        #expect(ScenePractice.status(Fixture.scene, book: book, today: today) == .reviewLater(due: tomorrow))
        #expect(ScenePractice.status(Fixture.scene, book: book, today: tomorrow) == .reviewDue(count: 2))

        book.questions[ids[0]] = QuestionProgress(stage: .reviewed)
        book.questions[ids[1]] = QuestionProgress(stage: .reviewed)
        #expect(ScenePractice.status(Fixture.scene, book: book, today: tomorrow) == .complete)
    }
}

@MainActor
struct SceneProgressStoreTests {
    private let alice = UUID()
    private let bob = UUID()

    @Test
    func progressSurvivesARelaunch() {
        let directory = Fixture.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = SceneProgressStore(directory: directory)
        store.use(account: self.alice)
        let progress = QuestionProgress(
            stage: .awaitingReview(due: LocalDay(year: 2026, month: 11, day: 9)),
            usedPhrasingIds: [PhrasingID(rawValue: "s.q0.p1")]
        )
        store.update {
            $0.questions[SceneQuestionID(rawValue: "s.q0")] = progress
            $0.cursors[SceneID(rawValue: "s")] = 1
        }

        let relaunched = SceneProgressStore(directory: directory)
        relaunched.use(account: self.alice)

        #expect(relaunched.book.progress(SceneQuestionID(rawValue: "s.q0")) == progress)
        #expect(relaunched.book.cursors[SceneID(rawValue: "s")] == 1)
    }

    @Test
    func eachAccountKeepsItsOwnProgressAcrossSignOutAndBack() {
        let directory = Fixture.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = SceneProgressStore(directory: directory)
        let question = SceneQuestionID(rawValue: "s.q0")

        store.use(account: self.alice)
        store.update { $0.questions[question] = QuestionProgress(stage: .reviewed) }
        store.reset()
        #expect(store.book == SceneProgressBook())

        store.use(account: self.bob)
        #expect(store.book.progress(question).stage == .new)
        store.update { $0.cursors[SceneID(rawValue: "s")] = 2 }
        store.reset()

        store.use(account: self.alice)
        #expect(store.book.progress(question).stage == .reviewed)
        #expect(store.book.cursors.isEmpty)
    }

    @Test
    func nothingIsWrittenWithoutAnAccount() {
        let directory = Fixture.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = SceneProgressStore(directory: directory)
        store.update { $0.cursors[SceneID(rawValue: "s")] = 1 }
        #expect(store.book.cursors.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: directory.path))
    }
}

@MainActor
struct ScenePracticeSessionTests {
    private func store() -> (SceneProgressStore, URL) {
        let directory = Fixture.temporaryDirectory()
        let store = SceneProgressStore(directory: directory)
        store.use(account: UUID())
        return (store, directory)
    }

    private let evening = { Fixture.date(2026, 11, 8, 20) }

    @Test
    func aWrongAnswerKeepsTheQuestionOpenUntilTheRightOne() {
        let (store, directory) = self.store()
        defer { try? FileManager.default.removeItem(at: directory) }
        let session = ScenePracticeSession(
            scene: Fixture.scene,
            store: store,
            now: self.evening,
            calendar: Fixture.calendar
        )

        session.answer("b")
        #expect(session.phase == .practising(step: 0, .answeredWrong(tried: ["b"])))
        session.answer("c")
        #expect(session.phase == .practising(step: 0, .answeredWrong(tried: ["b", "c"])))
        #expect(store.book.progress(SceneQuestionID(rawValue: "s.q0")).stage == .new)

        session.answer("a")
        #expect(session.phase == .practising(step: 0, .revealed(firstTry: false)))
        #expect(store.book.progress(SceneQuestionID(rawValue: "s.q0")).stage == .awaitingReview(due: LocalDay(
            year: 2026,
            month: 11,
            day: 9
        )))
    }

    @Test
    func quittingMidSceneResumesAtTheSameQuestion() {
        let (store, directory) = self.store()
        defer { try? FileManager.default.removeItem(at: directory) }
        let first = ScenePracticeSession(
            scene: Fixture.scene,
            store: store,
            now: self.evening,
            calendar: Fixture.calendar
        )
        first.answer("a")
        first.next()
        first.answer("b")
        #expect(first.currentStep?.questionIndex == 1)

        let resumed = ScenePracticeSession(
            scene: Fixture.scene,
            store: store,
            now: self.evening,
            calendar: Fixture.calendar
        )

        #expect(resumed.currentStep?.questionIndex == 1)
        #expect(resumed.steps.map(\.questionIndex) == [1, 2])
    }

    @Test
    func resumingTheNextDayFinishesTheRestBeforeReviewing() {
        let (store, directory) = self.store()
        defer { try? FileManager.default.removeItem(at: directory) }
        let first = ScenePracticeSession(
            scene: Fixture.scene,
            store: store,
            now: self.evening,
            calendar: Fixture.calendar
        )
        first.answer("a")
        first.next()

        let nextDay = ScenePracticeSession(
            scene: Fixture.scene,
            store: store,
            now: { Fixture.date(2026, 11, 9, 9) },
            calendar: Fixture.calendar
        )

        #expect(nextDay.steps.map(\.questionIndex) == [1, 2, 0])
        #expect(nextDay.steps.map(\.mode) == [.first, .first, .review])
        #expect(nextDay.steps[2].phrasing.id.rawValue == "s.q0.p3")
    }

    @Test
    func finishingTheSceneClearsTheCursorAndSchedulesTomorrow() {
        let (store, directory) = self.store()
        defer { try? FileManager.default.removeItem(at: directory) }
        let session = ScenePracticeSession(
            scene: Fixture.scene,
            store: store,
            now: self.evening,
            calendar: Fixture.calendar
        )
        for (index, _) in Fixture.scene.questions.enumerated() {
            if index == 1 { session.answer("b") }
            session.answer("a")
            session.next()
        }

        #expect(session.phase == .finished(.init(
            results: [1, 0, 2].map { index in
                .init(question: Fixture.scene.questions[index], wrongTries: index == 1 ? 1 : 0)
            },
            status: .reviewLater(due: LocalDay(year: 2026, month: 11, day: 9))
        )))
        #expect(store.book.cursors[SceneID(rawValue: "s")] == nil)
        #expect(store.book.lastSceneId == SceneID(rawValue: "s"))
    }
}

/// The staged screens answer with a reply or a finished machine instead of a
/// choice; the session settles them the same way.
@MainActor
struct StagedAnswerTests {
    private func session() -> (ScenePracticeSession, SceneProgressStore, URL) {
        let directory = Fixture.temporaryDirectory()
        let store = SceneProgressStore(directory: directory)
        store.use(account: UUID())
        let session = ScenePracticeSession(
            scene: Fixture.scene,
            store: store,
            now: { Fixture.date(2026, 11, 8, 20) },
            calendar: Fixture.calendar
        )
        return (session, store, directory)
    }

    private func reply(_ id: String, fits: Bool) -> StageReply {
        let text = LocalizedText(zhHant: id, zhHans: id, en: id)
        return StageReply(id: id, ja: id, meaning: text, fits: fits, result: text, show: nil)
    }

    @Test
    func aReplyThatDoesNotFitIsATryAndTheQuestionStaysOpen() {
        let (session, store, directory) = self.session()
        defer { try? FileManager.default.removeItem(at: directory) }
        session.reply(self.reply("cold", fits: false))
        #expect(session.phase == .practising(step: 0, .answeredWrong(tried: ["reply:cold"])))
        #expect(store.book.progress(SceneQuestionID(rawValue: "s.q0")).stage == .new)
        session.reply(self.reply("hot", fits: true))
        #expect(session.phase == .practising(step: 0, .revealed(firstTry: false)))
        #expect(store.book.progress(SceneQuestionID(rawValue: "s.q0")).stage != .new)
    }

    @Test
    func theSummaryPutsWhatWasMissedOrHelpedFirstEachOnce() {
        let (session, _, directory) = self.session()
        defer { try? FileManager.default.removeItem(at: directory) }
        session.reply(self.reply("ok", fits: true))
        session.next()
        session.noteHint()
        session.reply(self.reply("ok", fits: true))
        session.next()
        session.noteHint()
        session.reply(self.reply("no", fits: false))
        session.reply(self.reply("ok", fits: true))
        session.next()
        guard case let .finished(summary) = session.phase else {
            Issue.record("not finished")
            return
        }
        #expect(summary.results.map(\.question.id.rawValue) == ["s.q1", "s.q2", "s.q0"])
        #expect(summary.results.map(\.usedHint) == [true, true, false])
        #expect(summary.results.map(\.wrongTries) == [0, 1, 0])
    }

    @Test
    func aMachineFinishedTwiceRecordsOnce() {
        let (session, store, directory) = self.session()
        defer { try? FileManager.default.removeItem(at: directory) }
        session.finish(.paid(.card, change: 0), fits: true)
        let after = store.book
        session.finish(.paid(.card, change: 0), fits: true)
        #expect(store.book == after)
        #expect(session.phase == .practising(step: 0, .revealed(firstTry: true)))
    }

    @Test
    func askingAgainPlaysUnheardPhrasingsAndTomorrowsReviewSkipsThem() {
        let (session, store, directory) = self.session()
        defer { try? FileManager.default.removeItem(at: directory) }
        #expect(session.askAgain()?.audio == "s.q0.p2.mp3")
        #expect(session.askAgain()?.audio == "s.q0.p3.mp3")
        #expect(session.askAgain()?.audio == "s.q0.p4.mp3")
        #expect(session.askAgain() == nil)
        let id = SceneQuestionID(rawValue: "s.q0")
        #expect(store.book.progress(id).usedPhrasingIds.count == 3)
        session.reply(self.reply("ok", fits: true))
        #expect(store.book.progress(id).usedPhrasingIds.count == 4)
    }

    @Test
    func aReviewAfterOneRepeatPicksTheOtherUnheardPhrasing() {
        let (session, store, directory) = self.session()
        defer { try? FileManager.default.removeItem(at: directory) }
        _ = session.askAgain()
        _ = session.askAgain()
        session.reply(self.reply("ok", fits: true))
        let tomorrow = ScenePracticeSession(
            scene: Fixture.scene,
            store: store,
            now: { Fixture.date(2026, 11, 9, 9) },
            calendar: Fixture.calendar
        )
        let review = tomorrow.steps.first { $0.questionIndex == 0 }
        #expect(review?.mode == .review)
        #expect(review?.phrasing.id.rawValue == "s.q0.p4")
    }
}

/// Trips through a staged scene: a pass meets only its trip's 問句, and a
/// trip not taken does not hold the scene open.
@MainActor
struct SceneRouteTests {
    private static let scene: PracticeScene = {
        let steps = ["s.q0", "s.q1", "s.q2"].map { "\"\($0)\":{\"background\":\"bg\"}" }.joined(separator: ",")
        let route = { (id: String, optional: Bool, questions: [String]) in
            let list = questions.map { "\"\($0)\"" }.joined(separator: ",")
            let text = "{\"zh-Hant\":\"t\",\"zh-Hans\":\"t\",\"en\":\"t\"}"
            return "{\"id\":\"\(id)\",\"title\":\(text),\"intent\":\(text),\"enter\":\(text),"
                + "\"questions\":[\(list)],\"optional\":\(optional)}"
        }
        let json = """
        {"schemaVersion":2,"id":"s","revision":1,"access":"free",
         "title":{"zh-Hant":"t","zh-Hans":"t","en":"t"},
         "summary":{"zh-Hant":"s","zh-Hans":"s","en":"s"},
         "questions":[\(["s.q0", "s.q1", "s.q2"].map(Fixture.question).joined(separator: ","))],
         "stage":{"routes":[\(route("plain", false, ["s.q1", "s.q0"])),\(route("beer", true, ["s.q2", "s.q0"]))],
                  "steps":{\(steps)}}}
        """
        do {
            return try JSONDecoder().decode(PracticeScene.self, from: Data(json.utf8))
        } catch {
            preconditionFailure("fixture scene does not decode: \(error)")
        }
    }()

    private let today = LocalDay(year: 2026, month: 11, day: 9)

    private func id(_ raw: String) -> SceneQuestionID {
        SceneQuestionID(rawValue: raw)
    }

    @Test
    func aPassMeetsOnlyItsTripInTheTripsOrder() {
        let stage = Self.scene.stage
        let plain = ScenePractice.plan(
            Self.scene,
            book: SceneProgressBook(),
            today: self.today,
            route: stage?.route("plain")
        )
        #expect(plain.map(\.questionIndex) == [1, 0])
        let beer = ScenePractice.plan(
            Self.scene,
            book: SceneProgressBook(),
            today: self.today,
            route: stage?.route("beer")
        )
        #expect(beer.map(\.questionIndex) == [2, 0])
    }

    @Test
    func finishingTheDefaultTripFinishesTheSceneAndTheOtherTripStaysUnpractised() {
        var book = SceneProgressBook()
        book.questions[self.id("s.q0")] = QuestionProgress(stage: .reviewed)
        book.questions[self.id("s.q1")] = QuestionProgress(stage: .reviewed)
        #expect(ScenePractice.status(Self.scene, book: book, today: self.today) == .complete)
        #expect(book.progress(self.id("s.q2")).stage == .new)
        #expect(Self.scene.practised(in: book) == [true, true])
    }

    @Test
    func aQuestionFromTheOtherTripCountsOnceItHasBeenPractised() {
        var book = SceneProgressBook()
        book.questions[self.id("s.q0")] = QuestionProgress(stage: .reviewed)
        book.questions[self.id("s.q1")] = QuestionProgress(stage: .reviewed)
        book.questions[self.id("s.q2")] = QuestionProgress(stage: .awaitingReview(due: self.today))
        #expect(ScenePractice.status(Self.scene, book: book, today: self.today) == .reviewDue(count: 1))
        #expect(ScenePractice.suggestedRoute(Self.scene, book: book, today: self.today)?.id == "beer")
    }

    @Test
    func withNothingDueTheSuggestedTripIsTheDefault() {
        #expect(ScenePractice.suggestedRoute(Self.scene, book: SceneProgressBook(), today: self.today)?.id == "plain")
    }
}
