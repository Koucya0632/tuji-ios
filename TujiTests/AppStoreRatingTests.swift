import Foundation
import Testing
@testable import Tuji

struct AppStoreRatingPolicyTests {
    private let start = Date(timeIntervalSince1970: 1_750_000_000)
    private let goodRound = StudyRoundOutcome(answered: 10, missed: 1, unsynced: 0, queueCleared: true)

    private func ledger(rounds: Int = 3, asked: String? = nil) -> AppStoreRatingLedger {
        AppStoreRatingLedger(firstRoundAt: self.start, roundsFinished: rounds, askedForVersion: asked)
    }

    private func shouldAsk(
        _ ledger: AppStoreRatingLedger,
        _ round: StudyRoundOutcome,
        daysLater: Double = 3
    )
        -> Bool
    {
        AppStoreRatingPolicy.shouldAsk(
            ledger: ledger,
            round: round,
            version: "1.3.3",
            now: self.start.addingTimeInterval(daysLater * 86_400)
        )
    }

    @Test
    func asksAfterAGoodRoundOnceTheUserHasSettledIn() {
        #expect(self.shouldAsk(self.ledger(), self.goodRound))
    }

    @Test
    func waitsForEnoughRoundsAndEnoughDays() {
        #expect(!self.shouldAsk(self.ledger(rounds: 2), self.goodRound))
        #expect(!self.shouldAsk(self.ledger(), self.goodRound, daysLater: 2.9))
        #expect(!self.shouldAsk(AppStoreRatingLedger(roundsFinished: 3), self.goodRound))
    }

    @Test
    func asksOnlyOncePerVersion() {
        #expect(!self.shouldAsk(self.ledger(asked: "1.3.3"), self.goodRound))
        // 上一版問過不算：新版本可以再問一次，次數上限交給系統。
        #expect(self.shouldAsk(self.ledger(asked: "1.3.2"), self.goodRound))
    }

    @Test
    func staysQuietAfterARoughRound() {
        let rough = StudyRoundOutcome(answered: 10, missed: 3, unsynced: 0, queueCleared: true)
        #expect(!self.shouldAsk(self.ledger(), rough))
        // 剛好兩成還算表現不錯。
        let borderline = StudyRoundOutcome(answered: 10, missed: 2, unsynced: 0, queueCleared: true)
        #expect(self.shouldAsk(self.ledger(), borderline))
    }

    @Test
    func staysQuietWhileThereIsStillSomethingToDeal() {
        let moreDue = StudyRoundOutcome(answered: 10, missed: 0, unsynced: 0, queueCleared: false)
        let unsynced = StudyRoundOutcome(answered: 10, missed: 0, unsynced: 1, queueCleared: true)
        let empty = StudyRoundOutcome(answered: 0, missed: 0, unsynced: 0, queueCleared: true)
        #expect(!self.shouldAsk(self.ledger(), moreDue))
        #expect(!self.shouldAsk(self.ledger(), unsynced))
        #expect(!self.shouldAsk(self.ledger(), empty))
    }
}

@MainActor
struct AppStoreRatingRecordTests {
    private let goodRound = StudyRoundOutcome(answered: 10, missed: 0, unsynced: 0, queueCleared: true)

    /// 每個測試一個獨立的 suite，不碰真正的 UserDefaults。
    private func defaults() throws -> UserDefaults {
        let name = "AppStoreRatingRecordTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    @Test
    func countsRoundsAcrossInstancesAndAsksOnTheThirdDay() throws {
        let defaults = try self.defaults()
        var now = Date(timeIntervalSince1970: 1_750_000_000)
        let clock = { now }

        let first = AppStoreRatingRecord(defaults: defaults, version: "1.3.3", now: clock)
        first.countRound()
        let early = first.finishReviewRound(self.goodRound)
        #expect(!early)

        // 重開 App：帳還在。
        now = now.addingTimeInterval(3 * 86_400)
        let later = AppStoreRatingRecord(defaults: defaults, version: "1.3.3", now: clock)
        #expect(later.ledger.roundsFinished == 2)
        let ready = later.finishReviewRound(self.goodRound)
        #expect(ready)
    }

    @Test
    func keepsAskingUntilTheRequestWasActuallySent() throws {
        let defaults = try self.defaults()
        var now = Date(timeIntervalSince1970: 1_750_000_000)
        let record = AppStoreRatingRecord(defaults: defaults, version: "1.3.3", now: { now })
        record.countRound()
        record.countRound()
        now = now.addingTimeInterval(4 * 86_400)

        // 使用者在視窗出現前離開：沒有 markAsked，下一輪還能問。
        let firstTry = record.finishReviewRound(self.goodRound)
        let secondTry = record.finishReviewRound(self.goodRound)
        #expect(firstTry)
        #expect(secondTry)

        record.markAsked()
        let afterAsking = record.finishReviewRound(self.goodRound)
        #expect(!afterAsking)
    }
}
