// 商店評分請求：什麼時候請使用者去 App Store 評分。
//
// 這裡的「評分」是 App Store 的星等，不是複習時的 困難／穩定／熟練 —— 那個在這個
// codebase 裡早就叫 rating 了，所以這個 module 的每個名字都帶 `AppStore`。
//
// 系統的評分視窗一年最多對同一個人出現三次，而且出不出現由系統決定，App 只能
// 「請求」。所以唯一能決定的是時機：在使用者剛得到好處的那一刻問，而且每個版本只問
// 一次。規則都在 `AppStoreRatingPolicy`，是純函式；`AppStoreRatingRecord` 只負責把
// 三個數字存進 UserDefaults。

import Foundation

/// 一輪結束時的樣子 —— 決定要不要問，只需要這四件事。
nonisolated struct StudyRoundOutcome: Equatable {
    /// 這一輪答了幾個字。
    let answered: Int
    /// 其中答錯過（被重考）的字數。
    let missed: Int
    /// 沒送到伺服器、停在離線佇列裡的答案數。
    let unsynced: Int
    /// 這一輪之後還有沒有到期的字。還有的話使用者正在清積壓，別打斷。
    let queueCleared: Bool
}

/// 這台裝置上，跟評分請求有關的全部記憶。
nonisolated struct AppStoreRatingLedger: Equatable {
    /// 第一次完成一輪的時間。「用了幾天」從這裡算起。
    var firstRoundAt: Date?
    /// 完成過幾輪（學新字或複習都算）。
    var roundsFinished = 0
    /// 已經問過的最新版本；同一個版本不問第二次。
    var askedForVersion: String?
}

nonisolated enum AppStoreRatingPolicy {
    /// 太早問，使用者還沒感受到間隔重複的效果。
    static let minimumRounds = 3
    static let minimumDays = 3
    /// 答錯過的字超過這個比例，就不是「表現不錯的一輪」。
    static let maximumMissRate = 0.2

    /// `ledger` 是已經把這一輪算進去之後的帳。
    static func shouldAsk(
        ledger: AppStoreRatingLedger,
        round: StudyRoundOutcome,
        version: String,
        now: Date
    )
        -> Bool
    {
        guard ledger.askedForVersion != version else { return false }
        guard ledger.roundsFinished >= self.minimumRounds else { return false }
        guard let firstRoundAt = ledger.firstRoundAt,
              now.timeIntervalSince(firstRoundAt) >= Double(self.minimumDays) * 86_400
        else { return false }
        // 有答案沒同步時，結算畫面正在顯示一則提醒；那不是開口要星星的時候。
        guard round.queueCleared, round.unsynced == 0, round.answered > 0 else { return false }
        return Double(round.missed) / Double(round.answered) <= self.maximumMissRate
    }
}

/// Device-global，跟 `OnboardingState.tourDone` 一樣：系統的次數上限是算在 Apple ID
/// 上的，換帳號登入不該讓同一個人再被問一次。
@MainActor
final class AppStoreRatingRecord {
    static let shared = AppStoreRatingRecord()

    /// 使用者主動去評分的入口（設定頁）。跟系統視窗不同，這個連結永遠會打開商店。
    static let writeReviewURL = URL(string: "https://apps.apple.com/app/id6781950004?action=write-review")
        ?? URL(fileURLWithPath: "/")

    private let firstRoundKey = "tuji.appStoreRating.firstRoundAt"
    private let roundsKey = "tuji.appStoreRating.roundsFinished"
    private let askedKey = "tuji.appStoreRating.askedForVersion"

    private let defaults: UserDefaults
    private let version: String
    private let now: () -> Date

    init(
        defaults: UserDefaults = .standard,
        version: String = AppInfo.shortVersion,
        now: @escaping () -> Date = Date.init
    ) {
        self.defaults = defaults
        self.version = version
        self.now = now
    }

    var ledger: AppStoreRatingLedger {
        AppStoreRatingLedger(
            firstRoundAt: self.defaults.object(forKey: self.firstRoundKey) as? Date,
            roundsFinished: self.defaults.integer(forKey: self.roundsKey),
            askedForVersion: self.defaults.string(forKey: self.askedKey)
        )
    }

    /// 記一輪。學新字的結算只呼叫這個 —— 它算進「用了多久」，但不在那裡問。
    func countRound() {
        if self.defaults.object(forKey: self.firstRoundKey) == nil {
            self.defaults.set(self.now(), forKey: self.firstRoundKey)
        }
        self.defaults.set(self.defaults.integer(forKey: self.roundsKey) + 1, forKey: self.roundsKey)
    }

    /// 記一輪複習，並回答現在適不適合問。回 true 不代表已經問了：呼叫端真的送出請求
    /// 之後要呼叫 `markAsked()`，否則使用者在視窗出現前離開，這個版本的機會就白白用掉。
    func finishReviewRound(_ round: StudyRoundOutcome) -> Bool {
        self.countRound()
        return AppStoreRatingPolicy.shouldAsk(
            ledger: self.ledger,
            round: round,
            version: self.version,
            now: self.now()
        )
    }

    func markAsked() {
        self.defaults.set(self.version, forKey: self.askedKey)
    }
}
